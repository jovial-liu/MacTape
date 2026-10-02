# Security policy

MacTape can replay input across applications. We treat any bypass of user intent, secret capture, or unexpected command execution as a security issue.

## Supported versions

Security fixes currently target the latest release and `main`.

## Reporting a vulnerability

Please use GitHub's **Report a vulnerability** flow under the repository's Security tab. Do not include secrets, personal workflows, or private screenshots in a public issue.

Useful reports include:

- the affected version and macOS version;
- a minimal, redacted `.mactape` file if relevant;
- expected versus observed behavior;
- whether the issue can execute a step that was not visibly approved.

We aim to acknowledge a report within 72 hours. This is a volunteer project, so remediation timing depends on severity and reproducibility.

## Explicit non-goals

- MacTape is not a security boundary against a malicious local user.
- Imported workflows are untrusted input and must be reviewed before live replay.
- A successful dry run does not prove another app will keep an identical Accessibility tree forever.
