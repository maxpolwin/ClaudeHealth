# ClaudeHealth

Native macOS dashboard for your **Claude Code** usage. Token volume, daily activity heatmap, hour-of-day patterns, per-project + per-model breakdown, cache hit ratio, sessions, live velocity. **100 % local — no network calls, no telemetry.**

UX: a Grammarly-style floating bubble lives at the edge of your screen, color-shifts as you approach a daily token goal (Apple-Health-Activity-style ring with overflow), and clicks open into a full Apple-Health-aesthetic dashboard. No Dock icon, no menu bar bloat. Reads `~/.claude/projects/*/*.jsonl` directly. Nothing leaves your Mac.

> Built with Swift 6 + SwiftUI + Apple's Charts framework. Zero third-party dependencies.

## Status

v1.0 — public release. Code-signed (ad-hoc by default; Developer ID + notarization supported). Hardened-runtime, explicit-deny entitlements, self-verifying signature on launch, anti-debug in Release builds. See **Hardening** below.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ (for `xcodebuild` and SwiftUI Charts)
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — only needed if you change `project.yml`

## Build & install (Apple Development cert)

The project is preconfigured for the `Apple Development: Max Polwin (QXT62Q4V34)` cert / team `PDPT7GQQWN`. To use a different developer:

1. Edit [project.yml](project.yml) — change `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY`.
2. `xcodegen` (regenerates `ClaudeHealth.xcodeproj`).

Then:

```bash
./build.sh --install        # signed Release build → /Applications/ClaudeHealth.app
open /Applications/ClaudeHealth.app
```

That's it — the app is signed by your Apple Development cert, so it launches without Gatekeeper warnings on your registered Mac.

### Other build modes

```bash
./build.sh                  # Debug build into build/, no install
./build.sh --run            # Debug build + launch from build/
./build.sh --release        # Release build into build/, no install
./build.sh --notarize       # Release + Developer ID + notarize + staple (see below)
```

### Working in Xcode

```bash
open ClaudeHealth.xcodeproj
```

Cmd+R runs the Debug scheme. Signing is preconfigured under the **Signing & Capabilities** tab — switch certs there if you want.

## Distribution path (Developer ID + notarization)

To share the app with others (or run on Macs not registered to your dev account), you need a **Developer ID Application** cert + notarization. The team-pinned Designated Requirement in `build.sh` is already written to accept either Apple Development *or* Developer ID Application certs from team `PDPT7GQQWN` — no other team, no Distribution / Mac App Store certs — so you can flip between them without re-issuing the DR.

### One-time setup

1. **Create the Developer ID Application cert** (you don't have one yet):
   - Open Keychain Access → menu **Certificate Assistant → Request a Certificate from a Certificate Authority** → "Saved to disk" + "Let me specify key pair information" → 2048-bit RSA. Save the `.certSigningRequest`.
   - Go to https://developer.apple.com/account/resources/certificates/add → pick **Developer ID Application** → upload the CSR → download the resulting `.cer`.
   - Double-click the `.cer` to install. Verify with:
     ```bash
     security find-identity -v -p codesigning | grep "Developer ID Application"
     ```

2. **Store notarytool credentials in your login keychain** (one-time, lives in Keychain — encrypted at rest):
   ```bash
   xcrun notarytool store-credentials ClaudeHealthNotary \
       --apple-id "you@example.com" \
       --team-id PDPT7GQQWN
   # prompts for an app-specific password from appleid.apple.com
   # (NOT your real Apple ID password — generate a 4-word app password)
   ```

### Each release

```bash
SIGN_IDENTITY="Developer ID Application: Max Polwin (PDPT7GQQWN)" \
NOTARY_PROFILE=ClaudeHealthNotary \
    ./build.sh --notarize
```

This produces a Release build, re-signs with Developer ID + the team-pinned DR, submits to Apple's notary service (1–10 min wait), and staples the resulting ticket so the app verifies offline. Verify the result with:

```bash
spctl -a -vv -t install build/ClaudeHealth.app
# expect:  build/ClaudeHealth.app: accepted
#          source=Notarized Developer ID
xcrun stapler validate build/ClaudeHealth.app
# expect:  The validate action worked!
```

Then `cp -R build/ClaudeHealth.app /Applications/` and you're done — no Gatekeeper warnings on any Mac, and tampering with any sealed file invalidates the signature *and* the staple.

## Hardening

- **No network**: zero `URLSession`/`Network`/HTTP refs in source; no `NSAppTransportSecurity` exceptions; verifiable with `LuLu`.
- **No subprocess / dyn-loading**: no `Process()` / `dlopen` / `posix_spawn` in app sources.
- **Hardened Runtime ON**, with seven explicit-deny entitlements (`allow-jit`, `allow-unsigned-executable-memory`, `allow-dyld-environment-variables`, `disable-library-validation`, `disable-executable-page-protection`, `allow-relative-library-loads` + `app-sandbox`).
- **Self-verify on launch** via `SecStaticCodeCheckValidityWithErrors` (strict + nested-code + all-architectures). Tampered bundles trigger an alert.
- **Anti-debug**: `PT_DENY_ATTACH` in Release builds. Verified: `lldb -p $(pgrep ClaudeHealth)` → "Not allowed to attach."
- **Team-pinned Designated Requirement**: `subject.OU = "PDPT7GQQWN"` — survives Apple Development cert renewals.
- **Cache file 0600** via `open(O_CREAT, 0600)` + `fsync` + atomic `replaceItemAt` (no TOCTOU window).
- **Cache schema/bundle-id integrity guard**: a substituted `cache.json` is rejected and rebuilt from JSONL ground truth.
- **Bounded streaming JSONL parser**: 1 MiB / line, 100 MiB / file, 500 MiB / parse caps. Symlink escapes from `~/.claude/projects/` rejected; files opened by canonical resolved path.
- **OSLog with `.private` redaction** for token counts + budgets; filenames passed through `String.logSafe` to block log injection.
- **DYLD_* env-var audit** at launch: any DYLD_* that survived hardened runtime triggers a `Log.security.fault`.
- **Confetti panel**: at `.popUpMenu` level (not screen-saver), `sharingType = .none` (excluded from screen recording), `ignoresMouseEvents = true`.
- **Bundle integrity baseline**: `./build.sh --install` writes `build/checksums.txt` with SHA256 of binary + every bundled `.icns` so post-install tampering is one `diff` away from being detected.
- **Clean uninstall**: Settings → Advanced → "Uninstall ClaudeHealth…" unregisters the Login Item, deletes Application Support + UserDefaults, then quits — leaves no orphan persistence (verified via Objective-See's KnockKnock).

## First launch

Just `open /Applications/ClaudeHealth.app`. With Apple Development signing on your registered Mac there's no warning. With Developer ID + notarization there's no warning anywhere.

If you somehow get the "can't be opened" warning (e.g., copied an unsigned build from elsewhere):

```bash
xattr -dr com.apple.quarantine /Applications/ClaudeHealth.app
open /Applications/ClaudeHealth.app
```

## What you'll see

A small **floating bubble** in the top-right of your main display showing today's token count inside a progress ring (ring fills relative to your 30-day daily average).

### Bubble interactions

- **Click** → expands the dashboard alongside it.
- **Drag** → reposition; on release the bubble **snaps to the nearest screen edge** (Grammarly-style) with a native trackpad haptic.
- **Right-click** → context menu (Show Dashboard, Refresh Now, Settings…, Quit).
- **Hover** → tooltip with today / 7-day / 30-day totals + 5h-window status if you've set a budget.
- **Color** — the ring shifts **blue → green** as you approach the 5-hour usage limit you set in Settings. When you cross it, the ring pulses green and the screen fills with confetti for 5 seconds.

### Dashboard

12 cards in Apple Health style. Every card has an **(i)** info icon — hover for a plain-English explanation. Every chart has a **hover tooltip** showing the precise value under the cursor.

1. **Hero ring** — today vs 30-day average, % delta, current velocity
2. **Today / 7-day / 30-day** summary cards with period-over-period delta
3. **Live velocity** — tokens/min over the last 15 min + 60-min sparkline
4. **5-hour usage limit** — rolling-window usage vs your set budget; ring blue → green as you approach it; counts crossings
5. **Streak** — current + longest consecutive-day streak
6. **Year heatmap** — 53 weeks × 7 days, GitHub-style intensity
7. **Daily stacked bar** (last 30 days) — input / output / cache write / cache read with hover breakdown
8. **Hour × day-of-week heatmap** — when you actually use Claude
9. **By project** — top 7 projects + Other rollup
10. **By model** — donut with hover slice highlighting
11. **Cache hit ratio** — 30-day sparkline
12. **Sessions per day** — 30-day bars

Click outside or **Esc** to dismiss. **⌘R** to force-refresh. Auto-refreshes every **2 s** when transcript files change. Click the **share** icon (top-right of dashboard) to export the full dashboard as a Retina PNG via the system share sheet.

### Usage limit (rolling 5 hours)

In Settings → Usage limit, set the number of tokens you'd consider your 5-hour cap (e.g., `5000000`). Then:

- The bubble's ring color interpolates **blue → green** as you approach the limit (green = "filled up").
- When you cross the limit, ClaudeHealth logs a `LimitEvent` and fires **5 seconds of confetti** across the screen (click-through, doesn't block your work). Idempotent — won't re-fire until usage drops below the threshold.
- A counter in Settings shows how many crossings happened in the last 30 days. There's a "Test confetti now" button.

### Launch at startup

Settings → Startup → "Open ClaudeHealth at login" toggle. Uses macOS `SMAppService.mainApp.register()`. If macOS shows "Needs approval," open System Settings → General → Login Items and enable ClaudeHealth.

## Coverage — what ClaudeHealth sees

| Surface | Token data locally? | What ClaudeHealth shows |
|---|---|---|
| **Claude Code (CLI)** | ✅ yes — full per-turn breakdown | everything: tokens, cache hits, daily/hourly heatmaps, projects, models, velocity |
| **Claude Desktop App, agent mode (Cowork)** | ❌ no tokens (run in a sandboxed VM) | session metadata only: count per day + recent list (title, model, when) |
| **Claude Desktop App, normal chat (webview)** | ❌ no | nothing — webview offloads to claude.ai server |
| **Claude.ai in browser** | ❌ no | nothing — pure server-rendered |
| **Anthropic API directly** | n/a | nothing — out of scope |

For the **unified** plan gauge across all surfaces, use Anthropic's own page (Settings → Help → "Open Anthropic plan usage on claude.ai", or directly: https://claude.ai/settings/usage).

## Where data comes from

- **Transcripts**: `~/.claude/projects/<project-key>/*.jsonl`. Only `type == "assistant"` events with `message.usage` are kept.
- **Cowork agent sessions**: `~/Library/Application Support/Claude/local-agent-mode-sessions/**/local_*.json`. Session metadata only (title, model, timestamps); no token data is exposed by the desktop app outside the VM.
- **Cache**: `~/Library/Application Support/ClaudeHealth/cache.json` — per-file `(size, mtime)` index plus rolled-up aggregates. Cold start ≈ 1–3 s on a 65 MB transcript pile; warm restart < 100 ms.
- **Usage-limit log**: persisted in `UserDefaults` under `ClaudeHealth.limitEvents`. Each entry records when you crossed your set 5-hour budget, the budget at that time, and the tokens in the window.
- **No cost / pricing displays.** Removed by design — this app tracks token volume, not dollars.

## Privacy

- No network calls.
- No telemetry.
- No file writes outside `~/Library/Application Support/ClaudeHealth/`.
- Reads `~/.claude/projects/` only. Doesn't touch project source code.

## Quitting

Right-click the bubble → **Quit ClaudeHealth**, or click the status-bar waveform icon → **Quit**.

## Uninstall

```bash
pkill -x ClaudeHealth
rm -rf /Applications/ClaudeHealth.app
rm -rf ~/Library/Application\ Support/ClaudeHealth
defaults delete com.max.ClaudeHealth
```

## Project layout

```
ClaudeHealth/
├── project.yml                    # xcodegen source of truth
├── ClaudeHealth.xcodeproj/        # generated by xcodegen, committed
├── Package.swift                  # also works for swift build, no Xcode
├── build.sh                       # xcodebuild wrapper + notarize helper
├── Resources/
│   ├── ClaudeHealth.entitlements  # sandbox=false
│   └── GeneratedInfo.plist        # generated by xcodegen
└── Sources/ClaudeHealth/
    ├── App/                       # ClaudeHealthApp, AppDelegate, window controllers
    ├── Models/                    # TranscriptEntry, Record, Aggregates
    ├── Data/                      # parser, aggregator, pricing, cache, file watcher
    └── Views/
        ├── BubbleView.swift
        ├── DashboardView.swift
        ├── SettingsView.swift
        ├── Style/                 # HealthCard modifier, Palette
        └── Cards/                 # 10 dashboard cards
```

## App icon

The app icon (`Resources/AppIcon.icns`) is generated by `tools/MakeIcon.swift` using CoreGraphics. Re-run after design changes:

```bash
swift tools/MakeIcon.swift
xcodegen
./build.sh --install
```

The script produces a squircle with a blue → indigo gradient, a centered SF Symbol (`chart.line.uptrend.xyaxis`) in white, and a soft drop shadow at every required iconset resolution.

## Forking

If you fork ClaudeHealth and want to sign with your own Apple Developer account:

1. Create your own Apple Development (or Developer ID Application) cert via Keychain Access → Certificate Assistant → "Request a Certificate from a Certificate Authority…" → upload to https://developer.apple.com/account/resources/certificates/add.
2. Replace these three values throughout the repo:
   - `PDPT7GQQWN` → your team identifier (`security find-identity -v -p codesigning` shows it in parentheses after the cert name)
   - `Apple Development: Max Polwin (QXT62Q4V34)` → your full cert subject CN
   - `Max Polwin` → your name (in `LICENSE`, `project.yml` properties, `Info.plist`)
3. Optionally rebrand: change `com.max.ClaudeHealth` → `com.<you>.ClaudeHealth` in `project.yml`, `Resources/ClaudeHealth.entitlements`, and `Sources/ClaudeHealth/App/Logging.swift`.
4. Run `xcodegen` to regenerate the Xcode project from your edited `project.yml`.
5. `./build.sh --install` — your fork now signs with your cert.

For ad-hoc-signed personal use (no Developer Account required), `./build.sh --install` works out of the box: build script falls back to ad-hoc signing when no `SIGN_IDENTITY` env var is set and the author's cert isn't in your keychain. The app still runs; macOS shows a one-time "Open anyway" dialog on first launch.

## Roadmap

- ClaudeHealth is **local-only**. No network sockets, no embedded HTTP server, no iPhone bridge — everything stays on this Mac for security.
- **v2 ideas** — Per-tool token attribution, CSV export, "main thread only" filter, real "API said no" usage-limit detection if Anthropic ever exposes a structured rate-limit field.

## Author

[Max Polwin](https://github.com/maxpolwin) — built scratching my own itch, polished publicly.

## License

[MIT](LICENSE) — do whatever, no warranty.
