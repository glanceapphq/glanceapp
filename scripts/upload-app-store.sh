#!/bin/bash
#
# Archives Glance and uploads it to App Store Connect, ready for TestFlight and App Review.
#
# Usage:
#   scripts/upload-app-store.sh              # archive and upload
#   scripts/upload-app-store.sh --export     # archive and export a signed .pkg locally, without uploading
#
# Needs the app record (bundle ID com.eugenekwasny.glance) to exist in App Store Connect, and an
# Apple ID of the team signed in under Xcode → Settings → Accounts. Signing is automatic: Xcode
# creates the Mac App Distribution certificate and provisioning profile on the first run.
#
# Each upload needs a Build number (CURRENT_PROJECT_VERSION) the app has never uploaded before.

set -euo pipefail

SCHEME="screenshot-app"
APP_NAME="Glance"
TEAM_ID="59MJ8J2KF3"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/screenshot-app.xcodeproj"
OUT="$ROOT/build/app-store"
ARCHIVE="$OUT/$APP_NAME.xcarchive"
EXPORT="$OUT/export"

destination="upload"
for argument in "$@"; do
    case "$argument" in
        --export) destination="export" ;;
        *) echo "Unknown option: $argument" >&2; exit 64 ;;
    esac
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

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
echo "$APP_NAME $VERSION ($BUILD)"

# The App Store only accepts sandboxed apps; catch a missing entitlement before Apple does.
entitlements="$(codesign -d --entitlements - --xml "$ARCHIVE/Products/Applications/$APP_NAME.app" 2>/dev/null)"
grep -q 'com.apple.security.app-sandbox' <<<"$entitlements" || { echo "The app isn't sandboxed" >&2; exit 1; }

if [[ "$destination" == "upload" ]]; then
    step "Uploading to App Store Connect"
else
    step "Exporting for the App Store"
fi
cat >"$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>$destination</string>
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

step "Done"
if [[ "$destination" == "upload" ]]; then
    echo "Uploaded $APP_NAME $VERSION ($BUILD). It shows up in App Store Connect → TestFlight after processing (usually 5–30 minutes)."
else
    echo "$(ls "$EXPORT"/*.pkg)"
fi
