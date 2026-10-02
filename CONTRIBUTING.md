# Contributing to MacTape

Thanks for helping make Mac automation understandable and trustworthy.

## Before you start

- Search existing issues and discussions.
- For a large feature or workflow-format change, open a proposal first.
- Keep pull requests focused and include tests for deterministic behavior.
- Never add telemetry, remote execution, or silent privilege escalation.

## Local development

MacTape requires macOS 14 or newer and Swift 6.

```bash
swift build --build-system native
swift test --build-system native --parallel
Scripts/run.sh
```

The last command creates an ad-hoc signed app bundle at `dist/MacTape.app` and opens it. macOS binds Accessibility and Input Monitoring grants to the app's identity, so use the bundled app—not alternating debug binaries—while testing permissions.

## Project principles

1. **Readable over magical.** A workflow should explain what it will do before it runs.
2. **Selectors over coordinates.** Prefer stable Accessibility attributes; do not add silent coordinate fallback.
3. **Local by default.** Recording and replay must not require an account or network service.
4. **Secrets stay references.** Never serialize passwords, tokens, or captured secure input into a workflow.
5. **Fail closed.** Ambiguous selectors and unsafe steps should stop instead of guessing.

## Pull requests

Before opening a PR:

```bash
swift test --build-system native --parallel
Scripts/test-cli.sh
swift build --build-system native -c release
Scripts/build-app.sh
```

Include:

- the user problem and chosen behavior;
- tests or a reason tests are not applicable;
- screenshots or a short recording for interface changes;
- privacy and permission impact, if any;
- migration notes for workflow-format changes.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
