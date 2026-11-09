#!/bin/bash
#
# Builds a Developer ID–signed, notarized DMG of Glance for direct download.
#
# Usage:
#   scripts/release-dmg.sh                    # archive, sign, notarize, staple, make the DMG
#   scripts/release-dmg.sh --skip-notarize    # same without notarization, for a quick local check
#
# Notarization needs a stored notarytool profile (once per Mac):
#   xcrun notarytool store-credentials glance-notary --apple-id <Apple ID> --team-id 59MJ8J2KF3
# Override the profile name with NOTARY_PROFILE=<name>.
#
# Output: build/release/Glance-<version>.dmg, plus an identical Glance.dmg. Attach both to the
# GitHub release: the unversioned one gives the landing page a link that never changes,
#   https://github.com/glanceapphq/glanceapp/releases/latest/download/Glance.dmg

set -euo pipefail

SCHEME="screenshot-app"
APP_NAME="Glance"
TEAM_ID="59MJ8J2KF3"
NOTARY_PROFILE="${NOTARY_PROFILE:-glance-notary}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/screenshot-app.xcodeproj"
OUT="$ROOT/build/release"
ARCHIVE="$OUT/$APP_NAME.xcarchive"
EXPORT="$OUT/export"
APP="$EXPORT/$APP_NAME.app"

notarize=true
for argument in "$@"; do
    case "$argument" in
        --skip-notarize) notarize=false ;;
        *) echo "Unknown option: $argument" >&2; exit 64 ;;
    esac
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# Submits a file for notarization and waits; prints Apple's log if it's rejected.
notarize_file() {
    local file="$1" output id
    output="$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)" || true
    echo "$output"
    if ! grep -q '"status" *: *"Accepted"' <<<"$output"; then
        id="$(sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' <<<"$output" | head -1)"
        [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" || true
        echo "Notarization failed for $file" >&2
        exit 1
    fi
}

if $notarize && ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "No notarytool profile named '$NOTARY_PROFILE'. Create it with:" >&2
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <Apple ID> --team-id $TEAM_ID" >&2
    echo "or run with --skip-notarize." >&2
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

step "Archiving"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE" \
    -quiet

INFO="$ARCHIVE/Products/Applications/$APP_NAME.app/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$INFO")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$INFO")"
DMG="$OUT/$APP_NAME-$VERSION.dmg"
LATEST_DMG="$OUT/$APP_NAME.dmg"
echo "$APP_NAME $VERSION ($BUILD)"

step "Exporting with Developer ID"
cat >"$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -allowProvisioningUpdates \
    -quiet

step "Checking the signature"
codesign --verify --deep --strict --verbose=2 "$APP"
# Read into variables first: `grep -q` stops reading early, which `pipefail` would report as a failure.
signature="$(codesign -dvv "$APP" 2>&1)"
entitlements="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)"
grep -E '^(Authority=Developer ID Application|TeamIdentifier|Timestamp)' <<<"$signature"
grep -q 'Authority=Developer ID Application' <<<"$signature" || { echo "Not signed with Developer ID" >&2; exit 1; }
grep -q 'flags=.*runtime' <<<"$signature" || { echo "Hardened runtime is off" >&2; exit 1; }
if grep -q 'get-task-allow' <<<"$entitlements"; then
    echo "The app has the get-task-allow (debugging) entitlement; notarization would reject it" >&2
    exit 1
fi

if $notarize; then
    # Notarize and staple the app itself too, so it passes Gatekeeper offline after being copied out of the DMG.
    step "Notarizing the app"
    ditto -c -k --keepParent "$APP" "$OUT/$APP_NAME.zip"
    notarize_file "$OUT/$APP_NAME.zip"
    xcrun stapler staple "$APP"
    rm "$OUT/$APP_NAME.zip"
fi

step "Creating the DMG"
STAGING="$OUT/dmg"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" -quiet
rm -rf "$STAGING"
# The app was signed by the export; sign the DMG with the same team's Developer ID certificate.
identity="$(security find-identity -v -p codesigning | grep "Developer ID Application: .*($TEAM_ID)" | head -1 | awk '{print $2}')"
[[ -n "$identity" ]] || { echo "No Developer ID Application certificate for team $TEAM_ID in the keychain" >&2; exit 1; }
codesign --sign "$identity" --timestamp "$DMG"

if $notarize; then
    step "Notarizing the DMG"
    notarize_file "$DMG"
    xcrun stapler staple "$DMG"

    step "Gatekeeper check"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
    spctl --assess --type execute --verbose=2 "$APP"
fi

# Copied last, so it includes the stapled notarization ticket.
cp "$DMG" "$LATEST_DMG"

step "Done"
echo "$DMG"
echo "$LATEST_DMG (same file, for the stable download link)"
echo "SHA-256: $(shasum -a 256 "$DMG" | cut -d ' ' -f 1)"
echo "Size: $(du -h "$DMG" | cut -f 1)"
$notarize || echo "Not notarized: other Macs will refuse to open it. Run without --skip-notarize for a release."
