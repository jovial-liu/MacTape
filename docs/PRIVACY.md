# Privacy

MacTape is designed around a simple rule: **record the action, not the person's private content**.

## What MacTape observes

Only while recording is visibly active, MacTape may observe:

- mouse clicks and their screen positions;
- keyboard shortcuts with qualifying modifiers (Command, Control, or Function by default; Option-only capture is disabled);
- Accessibility metadata for the clicked interface element, such as app bundle ID, role, label, identifier, and frame.

Ordinary typed text is not recorded. Secure field values are not read. Text steps must be added deliberately and may refer to a runtime variable instead of storing a value. Labels, window titles, and app-provided metadata can still disclose context even when field values are excluded.

## What stays on the Mac

Workflows, selectors, and settings stay local. The app contains no analytics SDK, advertising SDK, account system, or update tracker. The engine returns structured run records without resolved variable values. Do not assume local files are encrypted.

Exporting a workflow creates a human-readable JSON document. Review it before sharing: labels, window titles, app identifiers, file paths, and manually entered values can still reveal context.

## Permissions

- **Accessibility** lets MacTape identify interface controls and perform approved actions during replay.
- **Input Monitoring** lets MacTape observe clicks and modifier shortcuts while recording.

You can revoke either permission at any time in System Settings → Privacy & Security. Without them, the editor, validation, import, and export features continue to work.

## Network policy

The core app does not make network requests for recording or replay. A workflow can still interact with an app that sends data over the network; explicitly authorized shell code also runs with the user's authority. “Local-first” is not a network firewall. A future optional update checker or community integration must be isolated, disclosed, disabled by default, and reviewed separately before inclusion.
