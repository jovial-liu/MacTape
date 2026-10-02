import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var workflowPendingDeletion: EditableWorkflow?

    var body: some View {
        List(selection: $model.selection) {
            Section {
                Label("Welcome", systemImage: "sparkles")
                    .tag(SidebarSelection.welcome)
                    .accessibilityLabel("Welcome")

                HStack {
                    Label("Templates", systemImage: "square.grid.2x2")
                    Spacer(minLength: 8)
                    Text(model.templates.count, format: .number)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.primary.opacity(0.06), in: Capsule())
                        .accessibilityLabel("\(model.templates.count) templates")
                }
                .tag(SidebarSelection.templates)
            }

            Section("My Tapes") {
                if model.filteredWorkflows.isEmpty {
                    Text(model.sidebarSearch.isEmpty ? "No tapes yet" : "No matching tapes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .listRowBackground(Color.clear)
                        .accessibilityLabel(model.sidebarSearch.isEmpty ? "No tapes yet" : "No matching tapes")
                } else {
                    ForEach(model.filteredWorkflows) { workflow in
                        WorkflowSidebarRow(workflow: workflow)
                            .tag(SidebarSelection.workflow(workflow.id))
                            .contextMenu {
                                Button {
                                    model.selection = .workflow(workflow.id)
                                    model.duplicateSelectedWorkflow()
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    workflowPendingDeletion = workflow
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 210, ideal: 244, max: 310)
        .searchable(text: $model.sidebarSearch, placement: .sidebar, prompt: "Search tapes")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.createBlankWorkflow()
                } label: {
                    Label("New Tape", systemImage: "plus")
                }
                .help("Create a new tape")
                .accessibilityLabel("Create a new tape")
            }
        }
        .alert(
            "Delete “\(workflowPendingDeletion?.name ?? "Tape")”?",
            isPresented: Binding(
                get: { workflowPendingDeletion != nil },
                set: { if !$0 { workflowPendingDeletion = nil } }
            ),
            presenting: workflowPendingDeletion
        ) { workflow in
            Button("Delete", role: .destructive) {
                model.deleteWorkflow(id: workflow.id)
                workflowPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                workflowPendingDeletion = nil
            }
        } message: { _ in
            Text("This removes the workflow definition. It does not delete files or undo actions the tape previously performed.")
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                TapeLogoView(size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MacTape")
                        .font(.caption.weight(.semibold))
                    Text("Local by design")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Open Settings")
                .accessibilityLabel("Open Settings")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}

private struct WorkflowSidebarRow: View {
    let workflow: EditableWorkflow

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(workflow.accent.color.opacity(0.14))
                Image(systemName: "recordingtape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(workflow.accent.color)
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(workflow.enabledStepCount) active steps")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workflow.name), \(workflow.enabledStepCount) active steps")
    }
}
