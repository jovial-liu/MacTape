# Architecture

MacTape separates deterministic workflow data from permission-sensitive macOS automation.

```text
┌──────────────────────┐
│ SwiftUI application  │  editor · templates · dry-run console
└──────────┬───────────┘
           │
┌──────────▼───────────┐
│ MacTapeCore          │  Codable model · validation · storage
├──────────────────────┤
│ Recorder             │  CGEventTap → AX selector snapshots
│ Resolver             │  selector scoring → accessible element
│ Runner               │  dry-run / replay events / cancellation
└──────────┬───────────┘
           │
┌──────────▼───────────┐
│ macOS frameworks     │  Accessibility · CoreGraphics · AppKit
└──────────────────────┘
```

## Targets

- `MacTapeCore`: models, JSON format, storage, validation, recording, selector resolution, and replay.
- `MacTapeApp`: native SwiftUI editing and execution interface.
- `mactape`: structural validation, inspection, formatting, and library listing for scripts and CI. Desktop dry runs are initiated in the app.

There are no runtime package dependencies.

## Selector strategy

A click is not just an `(x, y)` coordinate. MacTape stores a description of the Accessibility element: bundle identifier, role, stable identifier, title or description, and hierarchy hints. Recorded screen positions do not become coordinate-only replay actions.

At replay time the resolver:

1. limits the search to the expected application;
2. scores exact stable attributes above visible labels;
3. rejects ambiguous best matches;
4. rejects scores below the configured threshold;
5. stops the run when a target cannot be resolved.

Scores are weighted matching heuristics, not calibrated probabilities. A live click first tries the element's Accessibility action and may synthesize a mouse event at the resolved element's current frame; it never uses an old recorded coordinate as fallback.

## Concurrency

UI state is isolated to `@MainActor`. File writes and workflow execution use actors. Permission callbacks and event taps cross into structured app state through explicit `Sendable` values.

## Persistence

Each workflow is an independently exportable `.mactape` JSON file. The library lives at `~/Library/Application Support/MacTape/Workflows`. Writes use Foundation's atomic replacement. Damaged or noncanonical library entries are retained and reported by `WorkflowStore.scan()` without hiding valid tapes. Import arbitrary filenames through the app; library filenames use workflow UUIDs.

Run records contain step identities, status, timing, and safe diagnostics, not expanded action payloads. Runtime overrides are literal inputs; saved defaults may reference other declared variables.
