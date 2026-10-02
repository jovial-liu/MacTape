import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: model)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { workflowToolbar }
        .inspector(isPresented: $model.isInspectorVisible) {
            WorkflowInspectorView(model: model)
                .inspectorColumnWidth(min: 260, ideal: TapeMetrics.inspectorWidth, max: 380)
        }
        .sheet(isPresented: $model.showsPermissionOnboarding) {
            PermissionOnboardingView(model: model)
        }
        .alert("MacTape needs attention", isPresented: Binding(
            get: { model.userFacingError != nil },
            set: { if !$0 { model.userFacingError = nil } }
        )) {
            Button("OK") { model.userFacingError = nil }
        } message: {
            Text(model.userFacingError ?? "")
        }
        .task {
            await model.bootstrap()
        }
        .onChange(of: model.selection) { _, selection in
            guard case let .workflow(id) = selection,
                  let workflow = model.workflows.first(where: { $0.id == id })
            else { return }
            if let selected = model.selectedStepID,
               workflow.steps.contains(where: { $0.id == selected }) {
                return
            }
            model.selectedStepID = workflow.steps.first?.id
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .welcome:
            WelcomeView(model: model)
        case .templates:
            TemplateLibraryView(model: model)
        case let .workflow(id):
            if let workflow = model.workflowBinding(for: id) {
                WorkflowEditorView(model: model, workflow: workflow)
            } else {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Tape unavailable",
                    message: "The workflow may have been moved or deleted.",
                    buttonTitle: "Return to Welcome"
                ) {
                    model.selection = .welcome
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PageBackground())
            }
        }
    }

    @ToolbarContentBuilder
    private var workflowToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.toggleRecording()
            } label: {
                Label(
                    model.runPhase == .recording ? "Stop Recording" : "Record",
                    systemImage: model.runPhase == .recording ? "stop.circle.fill" : "record.circle"
                )
            }
            .tint(.red)
            .disabled(model.selectedWorkflow == nil || !model.canRecord)
            .help(model.runPhase == .recording ? "Stop recording" : "Record a workflow")
            .accessibilityHint("Recording is visible and can be stopped at any time")

            Button {
                requestRun(.dryRun)
            } label: {
                Label("Dry Run", systemImage: "play.slash")
            }
            .disabled(!model.canRunSelection)
            .help("Preview actions without performing them")
            .accessibilityHint("Does not perform workflow actions")

            Button {
                requestRun(.live)
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canRunSelection)
            .help("Run enabled steps")

            if model.runPhase.isActive {
                Divider()
                Button(action: model.stop) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .tint(.red)
                .help("Stop current activity")
            }
        }

        ToolbarItemGroup(placement: .secondaryAction) {
            Button {
                model.isConsoleVisible.toggle()
            } label: {
                Label("Run Console", systemImage: "terminal")
            }
            .disabled(model.selectedWorkflow == nil)
            .help(model.isConsoleVisible ? "Hide run console" : "Show run console")

            Button {
                model.isInspectorVisible.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .disabled(model.selectedWorkflow == nil)
            .help(model.isInspectorVisible ? "Hide inspector" : "Show inspector")
        }
    }

    private func requestRun(_ mode: RunMode) {
        model.start(mode)
    }
}
