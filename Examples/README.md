# Starter tapes

These are real workflow-format-1 files. Import them into MacTape and inspect every step before running.

| Tape | Live-run effect | Permissions |
| --- | --- | --- |
| `01-safe-wait.mactape` | Waits for 1.5 seconds; changes nothing | None |
| `02-textedit-draft.mactape` | Opens TextEdit, creates an unsaved note, types the supplied greeting | Accessibility |

The TextEdit example expects no open modal dialogs. Close any file picker and review the app state before replay. It uses a keyboard shortcut and focused typing, which are state-dependent; it is a teaching example, not a promise that every initial desktop state works. Do not put passwords in saved defaults.

```bash
swift run --build-system native mactape validate Examples/01-safe-wait.mactape
swift run --build-system native mactape inspect Examples/02-textedit-draft.mactape
```

Dry Run validates the currently visible desktop. It does not open applications, create documents, predict future UI states, or guarantee a subsequent live run.
