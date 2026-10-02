<div align="center">
  <img src="assets/MacTape-AppIcon-1024.png" width="152" alt="MacTape app icon">
  <h1>MacTape</h1>
  <p><strong>Record. Inspect. Replay.</strong></p>
  <p>A visual, local-first workflow recorder for macOS.</p>

  [![CI](https://github.com/jovial-liu/MacTape/actions/workflows/ci.yml/badge.svg)](https://github.com/jovial-liu/MacTape/actions/workflows/ci.yml)
  [![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111827?logo=apple)](https://support.apple.com/macos)
  [![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org)
  [![MIT](https://img.shields.io/badge/license-MIT-62e6bb)](LICENSE)
</div>

<p align="center">English · <a href="README.zh-CN.md">简体中文</a></p>

![MacTape — record, understand, replay](assets/social-preview-v2.png)

![MacTape timeline, step inspector, and a completed Dry Run](assets/screenshots/editor.png)

MacTape turns deliberately recorded clicks and shortcuts into editable, app-scoped steps. Inspect what happened, add explicit text and waits, then replay through macOS Accessibility.

It is the open-source middle ground between writing automation code and trusting an AI agent to improvise on your desktop.

## Why MacTape?

Most Mac automation tools make you choose:

- learn a scripting language;
- assemble actions that cannot reach a traditional Mac app; or
- let a model look at the screen and guess what to click.

MacTape records what you already know how to do. A click can become an inspectable selector such as “the **Export** button in Acme Editor,” each shortcut stays a shortcut, and unresolved or ambiguous matches stop the run. Accessibility support varies by application; this is not universal desktop understanding.

```text
You do it once  →  MacTape explains it  →  You review it  →  Replay
```

## What is already inside

- **Intentional recording** — captures clicks and modifier shortcuts only while the red recording state is visible.
- **Semantic selectors** — identifies controls by app, role, stable identifier, title, description, and hierarchy hints.
- **Dry Run** — checks selectors against the current desktop without clicking, typing, launching apps, or running shell commands.
- **Visual timeline** — reorder, disable, duplicate, inspect, and annotate individual steps.
- **Safe replay** — supports clicks, shortcuts, app launch, waits, element assertions, and explicit text variables.
- **Readable files** — `.mactape` is stable, formatted JSON that can be reviewed and version controlled.
- **Local-first** — no account, telemetry, upload, analytics SDK, or runtime dependency.
- **CLI companion** — validate, inspect, format, and list workflows from Terminal or CI.

> [!IMPORTANT]
> MacTape is an early developer preview, not a safety sandbox. Review every workflow before running it. A click or shortcut can still delete, submit, or send data. No screen-coordinate fallback is supported.

## Install

### Download the app

Download `MacTape-0.1.0.dmg` from [Releases](https://github.com/jovial-liu/MacTape/releases). This community preview is **ad-hoc signed, not Developer ID signed or notarized**. Only if you trust the source and have checked the release checksum, follow Apple's [per-app opening instructions](https://support.apple.com/en-gb/102445) under System Settings → Privacy & Security. Do not disable Gatekeeper globally. Building from source is also supported.

### Build from source

Requirements: macOS 14+, a Swift 6 toolchain and macOS SDK (Xcode or Command Line Tools).

```bash
git clone https://github.com/jovial-liu/MacTape.git
cd MacTape
swift test --build-system native --parallel
Scripts/run.sh
```

The app bundle is created at `dist/MacTape.app`. To build the CLI separately:

```bash
swift build --build-system native -c release --product mactape
.build/release/mactape help
```

For Apple silicon + Intel distribution: `UNIVERSAL=1 Scripts/package-dmg.sh`.

## Try it in two minutes

1. Open MacTape and import [`Examples/01-safe-wait.mactape`](Examples/01-safe-wait.mactape).
2. Inspect the two waits and choose **Dry Run**, then **Run**. This example changes nothing on your Mac.
3. To record your own tape, grant Accessibility and Input Monitoring when requested. Record a few clicks in a non-sensitive app, stop, and review the generated selectors.
4. For explicit text and variables, inspect the [TextEdit example](Examples/README.md). Nothing is automatically saved or sent by that example.

## A workflow stays understandable

The following is an abbreviated excerpt, not a complete importable document; use the [examples](Examples) for valid files.

```json
{
  "formatVersion" : 1,
  "name" : "Export the weekly report",
  "steps" : [
    {
      "action" : {
        "bundleIdentifier" : "com.example.Reporter",
        "type" : "openApp"
      },
      "isEnabled" : true
    },
    {
      "action" : {
        "selector" : {
          "identifier" : "export-button",
          "matchStrategy" : "exact",
          "role" : "AXButton",
          "title" : "Export"
        },
        "type" : "click"
      },
      "isEnabled" : true
    }
  ]
}
```

The actual format also includes stable IDs and timestamps. MacTape writes canonical, sorted JSON so changes produce useful Git diffs.

## Safety is product behavior

Desktop automation should never hide its authority.

- Ordinary typed text is **not recorded**.
- Secure field **values** are not read by the recorder or resolver.
- Engine run records omit expanded action payloads and variable values.
- Low-confidence or ambiguous selectors stop the run.
- Dry Run is always available and never clicks or types.
- Shell execution requires an explicit, content-bound capability in the Core API; unapproved commands are blocked.
- No coordinate-only fallback, hidden background recorder, or ordinary-text capture.
- Recording and replay continue to work with networking disabled.

Read the [privacy design](docs/PRIVACY.md) and [threat model](docs/THREAT-MODEL.md) for the precise boundaries.

## Know the boundaries

- **Not every app is accessible.** Custom canvases, games, web content, and unlabeled controls may not expose usable selectors. Drag, scroll, and gestures are not recorded in this preview.
- **Dry Run sees now, not the future.** It cannot create the screen that an earlier action would have opened. Open the relevant screen first; a successful preflight is not a guarantee of a successful live run.
- **Selectors are heuristics.** Match scores are not probabilities. Similar labels, changing application state, and focus-dependent shortcuts still require human review.
- **Secrets stay your responsibility.** Runtime inputs are not persisted by the runner, but manually entered text, defaults, labels, and exported files can contain sensitive information. Review before sharing.
- **No unattended automation promise.** Keep the desktop visible. Stop and fix a failed tape rather than relying on implicit recovery.

## Architecture

MacTape is native SwiftUI and AppKit with no third-party runtime packages.

```text
MacTapeApp       visual editor · permission onboarding · run console
    ↓
MacTapeCore      workflow model · recorder · resolver · runner · storage
    ↓
macOS            Accessibility · CoreGraphics · AppKit

mactape CLI      validation · inspection · canonical formatting
```

See [Architecture](docs/ARCHITECTURE.md) for selector resolution, concurrency, and persistence details.

## Project status

The `0.1` preview focuses on **record → inspect → dry run → replay → share**. Guided selector repair, breakpoints, reusable subflows, Keychain-backed secret references, and App Intent integration are future work, not current features.

The detailed plan lives in the [roadmap](docs/ROADMAP.md). Issues labeled [`good first issue`](https://github.com/jovial-liu/MacTape/labels/good%20first%20issue) are designed to be genuinely approachable.

## Contributing

Bug reports, accessible-app compatibility fixtures, UI polish, documentation, and focused pull requests are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) and follow the [Code of Conduct](CODE_OF_CONDUCT.md).

If you discover a way to capture secrets, bypass review, or execute an unapproved action, please follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## License

MacTape is available under the [MIT License](LICENSE).

<div align="center">
  <sub>Built for people who want automation they can understand.</sub>
</div>
