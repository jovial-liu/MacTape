import SwiftUI

@main
struct MacTapeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .preferredColorScheme(model.appearance.colorScheme)
                .frame(minWidth: 940, minHeight: 650)
                .onOpenURL { model.importWorkflow(from: $0) }
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            MacTapeCommands(model: model)
        }

        Settings {
            SettingsView(model: model)
                .preferredColorScheme(model.appearance.colorScheme)
        }

        MenuBarExtra {
            Text(model.runPhase.title)
            if model.runPhase.isActive {
                Button("Stop Current Activity", action: model.stop)
                    .disabled(model.isStopping)
            }
            Button("Show MacTape") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
        } label: {
            Label("MacTape: \(model.runPhase.title)", systemImage: model.runPhase == .recording ? "record.circle.fill" : "play.rectangle")
        }
    }
}

struct MacTapeCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tape") {
                model.createBlankWorkflow()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Import Tape…", action: model.importWorkflow)
                .keyboardShortcut("o", modifiers: .command)
                .disabled(model.runPhase.isActive)
            Button("Export Tape…", action: model.exportSelectedWorkflow)
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.selectedWorkflow == nil)
            Button("Export Run Record…", action: model.exportRunRecord)
                .disabled(model.lastRunRecord == nil)
        }

        CommandMenu("Tape") {
            Button(model.runPhase == .recording ? "Stop Recording" : "Record") {
                model.toggleRecording()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.selectedWorkflow == nil || !model.canRecord)

            Divider()

            Button("Dry Run") {
                model.start(.dryRun)
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!model.canRunSelection)

            Button("Run") {
                model.start(.live)
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!model.canRunSelection)

            Button("Stop") {
                model.stop()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(!model.runPhase.isActive)

            Divider()

            Button("Add Step") {
                model.addStep(kind: .click, after: model.selectedStepID)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.selectedWorkflow == nil)

            Button("Duplicate Step") {
                model.duplicateSelectedStep()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(model.selectedStep == nil)

            Button("Delete Step") {
                model.deleteSelectedStep()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model.selectedStep == nil)

            Divider()

            Button("Previous Step") {
                model.selectAdjacentStep(-1)
            }
            .keyboardShortcut(.upArrow, modifiers: .option)
            .disabled(model.selectedWorkflow == nil)

            Button("Next Step") {
                model.selectAdjacentStep(1)
            }
            .keyboardShortcut(.downArrow, modifiers: .option)
            .disabled(model.selectedWorkflow == nil)

            Button("Enable or Disable Step") {
                model.toggleSelectedStep()
            }
            .keyboardShortcut(.space, modifiers: [.command, .option])
            .disabled(model.selectedStep == nil)
        }

        CommandMenu("View") {
            Button(model.isConsoleVisible ? "Hide Run Console" : "Show Run Console") {
                model.isConsoleVisible.toggle()
            }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(model.selectedWorkflow == nil)

            Button(model.isInspectorVisible ? "Hide Inspector" : "Show Inspector") {
                model.isInspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(model.selectedWorkflow == nil)
        }
    }
}
