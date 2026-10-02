# Threat model

MacTape is intentionally powerful: an approved workflow can control other applications. Its design therefore assumes workflows are executable documents, not harmless media.

## Assets to protect

- the user's intent and control of replay;
- typed secrets and secure fields;
- local files and application data;
- integrity of imported workflows;
- trustworthy, non-misleading run history.

## Primary threats and mitigations

| Threat | Mitigation |
| --- | --- |
| Imported workflow hides a destructive step | Import does not execute; visible timeline and validation. User review remains essential |
| UI changed and selector hits the wrong control | Weighted matching, ambiguity rejection, dry run, stop on mismatch; heuristic matching is not proof of identity |
| Recording captures a password | Ordinary text capture disabled; secure field values excluded |
| Variable value leaks into logs | Engine events omit expanded action payloads and input values |
| Shell command changes after approval | Denied by default; Core capability binds the step ID and expanded shell payload |
| Old recorded coordinates hit an unexpected target | No coordinate-only replay; synthesized click must use a newly resolved element |
| A saved file changes outside the app | Runs use an in-memory snapshot, not a reread midway through execution |

## Trust boundaries

- macOS owns Accessibility and Input Monitoring consent.
- MacTape trusts system Accessibility metadata only as a hint, not a guarantee of target identity.
- Other applications may expose incomplete or unstable Accessibility trees.
- A local attacker who can replace the running binary or workflow files is outside the app's protection boundary.

## Safe defaults

- New and imported workflows open in edit mode.
- The prominent first action is Dry Run.
- Shell execution is denied without an explicit Core capability; coordinate-only replay is not supported.
- Recorder capture is visibly indicated and stops when the app exits.
- Failures stop the run instead of skipping ahead silently.

## Residual risk

MacTape is not sandboxed and cannot infer the meaning of arbitrary application controls. An approved click can submit, send, delete, or purchase. Shortcuts and untargeted text depend on application focus. A malicious application can lie through Accessibility metadata. Never treat dry-run success as authorization or as proof that a live run is safe.
