# Preview validation

Validated on October 3, 2026 using macOS 27, Swift 6.4, and Xcode's macOS SDK. Minimum deployment target is macOS 14; compatibility on a physical macOS 14 machine and physical Intel Mac has not been manually verified.

- 45 Core tests passed: model/JSON compatibility, variable handling, library recovery, selector candidate selection, shell authority, dry-run nonexecution, timeouts, and cancellation.
- 13 CLI smoke checks passed, including malformed options and canonical formatting.
- Universal app and CLI binaries contain `arm64` and `x86_64` slices.
- App bundle passed `codesign --verify --deep --strict`; its signature is ad-hoc, without Apple notarization.
- The packaged app launched successfully. The safe-wait example imported through document opening, persisted across relaunch, completed Dry Run, and completed a live run containing only waits.
- `assets/screenshots/editor.png` is captured from the packaged running application.
- GitHub CI builds, tests, checks the CLI, packages the app, and verifies its signature on a macOS runner.

Cross-application recording and interactive Accessibility replay require user-granted permissions. They have implementation and focused engine tests, but broad manual compatibility testing across applications remains preview work. Dry Run is a check of the current desktop, not a simulation of future screens.

The Swift package desktop product is named `MacTapeDesktop`; it is installed as `MacTape.app`. This avoids collisions with the `mactape` CLI on case-insensitive macOS filesystems. Build scripts select SwiftPM's native build system because the Swift 6.4 default builder produced an incremental dependency-file error in this checkout; newer toolchains may allow that workaround to be removed.
