# Contributing to ClaudeHealth

Thanks for your interest. ClaudeHealth is a small, single-purpose macOS utility — contributions are welcome but the scope is intentionally tight.

## What's in scope

- New visualizations of locally-observable Claude usage data
- Performance / parsing improvements
- Apple HIG / accessibility polish
- Security hardening (see the v1.2/1.3 plan in commit history)
- Bug fixes

## What's out of scope (won't merge)

- **Network calls of any kind.** ClaudeHealth is local-only by design — see the project's hardening posture in [README.md](README.md). PRs that add `URLSession`, sockets, telemetry, analytics, or auto-update mechanisms will be closed.
- **App Sandbox.** It would block the app from reading `~/.claude/projects/`, which is the entire point.
- **Cookie scraping / API-key features for tracking web/desktop chat.** See the README "Coverage" matrix for the rationale.
- **Cost-estimation displays.** Removed by design.
- **iOS / iPadOS targets.** Mac-only.

## Dev setup

```bash
git clone https://github.com/maxpolwin/ClaudeHealth.git
cd ClaudeHealth
brew install xcodegen        # one-time
xcodegen                     # generate ClaudeHealth.xcodeproj from project.yml
open ClaudeHealth.xcodeproj  # ⌘R to build & run (Debug, ad-hoc signed)
```

Or terminal-only:

```bash
./build.sh                   # Debug build → build/ClaudeHealth.app
./build.sh --run             # Debug build + launch
./build.sh --install         # Release build + copy to /Applications
```

## Project structure

```
Sources/ClaudeHealth/
├── App/         # NSApplicationDelegate, NSPanel/Window controllers, system glue
├── Data/        # JSONL parser, aggregator, cache, pricing constants, file watcher
├── Models/      # Codable types: TranscriptEntry, Record, Aggregates
└── Views/       # SwiftUI: BubbleView, DashboardView, SettingsView + Cards/

Resources/       # AppIcon-*.icns + entitlements + GeneratedInfo.plist (regenerated)
tools/           # MakeIcon.swift (generates icns) + MakeMenuBarPreviews.swift
project.yml      # source-of-truth for the Xcode project (xcodegen reads this)
build.sh         # build / install / notarize / dmg
```

## Editing rules

- **Files** — add new `.swift` files in the filesystem (not via Xcode's File → New). Run `xcodegen` afterward to refresh the project.
- **Build settings, entitlements, Info.plist** — edit `project.yml`, run `xcodegen`. Never edit `ClaudeHealth.xcodeproj/project.pbxproj` by hand or in Xcode's project settings UI; it gets blown away on next regen.
- **Resources** — drop into `Resources/`, list in `project.yml` under the target's `sources:` block.
- **No third-party Swift Packages.** ClaudeHealth ships with zero non-Apple dependencies. Keeping it that way.

## Code style

- Match the surrounding code; no separate style guide.
- Prefer SwiftUI over AppKit where there's a clean way.
- Use `Logger` (from `Sources/ClaudeHealth/App/Logging.swift`) — never `NSLog` or `print` for anything that ships in Release.
- For any value derived from filesystem (filenames, project keys), pass through `String.logSafe` before logging.

## Submitting changes

1. Fork + branch.
2. Build clean: `./build.sh` succeeds with no warnings.
3. PR with a one-paragraph description: what changed, why, what to verify.
4. For non-trivial changes, include a screenshot or a short clip of the affected UI.

## Code of conduct

Be civil. The maintainer reserves the right to close low-effort or out-of-scope PRs without lengthy discussion.
