# CLAUDE.md

Guidance for Claude Code working in this repository. Read `README.md` → "For developers" for the architecture and design notes.

## Project

Glance is a native macOS menu bar screenshot app (Swift 6 strict concurrency, SwiftUI + AppKit, ScreenCaptureKit), shipped on the Mac App Store and as a notarized DMG. It is sandboxed and fully offline: **never add networking, analytics, accounts or third-party SDKs.**

## Planning: ROADMAP.md + GitHub Issues

- `ROADMAP.md` is the public overview (Now / Next / Later). Titles only, one line each; Now items link to their issue. Keep it free of prices, paid tiers, dates and marketing plans: the repository is public.
- A GitHub issue is the spec for one task: why, what, implementation notes, acceptance criteria. Only the current and next iteration get issues; later ideas stay as one-liners in ROADMAP.md.
- Each release has a milestone (`v1.1`, `v1.2`, …) grouping its issues.
- New feature issues follow `.github/ISSUE_TEMPLATE/feature.md`.

## Working on an issue ("take issue #N")

1. Read the issue and its comments; ask if acceptance criteria are unclear before writing code.
2. Work on the branch you were given (or `feature/<N>-short-name` if none).
3. Implement, keeping the existing structure (`Capture/`, `Editor/`, `Services/`, …) and style: small types, doc comments on non-obvious decisions.
4. Add or update unit tests in `GlanceTests/`. Tests can't run on Linux; if you can't run `xcodebuild test`, say so explicitly.
5. Update `README.md` (features / shortcuts) for anything user-visible.
6. Open the PR with `Closes #N` in the description, and tick the issue's acceptance criteria that are met.
7. When an issue ships, tick it in `ROADMAP.md` (and move the release to "Shipped" once all its items are done).

## Conventions

- Commit messages: imperative, sentence case, no prefix (e.g. "Add aspect ratio presets to the editor").
- What the editor shows and what is exported must stay identical: both render `CompositionView`.
- Annotations live in screenshot coordinates, not canvas coordinates.
- Canvas mouse input is handled in AppKit (`CanvasInputView`), not SwiftUI gestures.
- User-facing text: English, sentence case, macOS terminology (e.g. "Settings", "Option").
