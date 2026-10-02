# CLI companion

The `mactape` executable never records or replays desktop actions. It is suitable for reviewing workflow changes in a terminal or macOS CI job.

```bash
swift build --build-system native -c release --product mactape
.build/release/mactape help
```

| Command | Purpose |
| --- | --- |
| `validate tape.mactape [--json]` | Decode format 1 and report structural findings. Shell authority and missing runtime inputs remain warnings; this does not authorize replay |
| `inspect tape.mactape` | Show steps and brief action summaries. Explicit text and command snippets are intentionally visible; do not paste output publicly without review |
| `format tape.mactape [--check]` | Write canonical JSON atomically, or check without changing the file |
| `list [--directory path]` | List valid library files, reporting skipped damaged/noncanonical entries to stderr |
| `version` | Show app and workflow-format versions |

Exit codes: `0` success; `1` command, decoding, or I/O error; `2` validation errors; `3` formatting differs with `--check`.

The default library is `~/Library/Application Support/MacTape/Workflows`. Import files through the app; the library uses UUID filenames. Validation is not a prediction of UI compatibility, and a structurally valid workflow can still perform harmful actions when replayed.

`Scripts/test-cli.sh` exercises the command interface using temporary files and harmless examples.
