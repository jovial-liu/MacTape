import SwiftUI

struct WorkflowEditorView: View {
    @ObservedObject var model: AppModel
    @Binding var workflow: EditableWorkflow

    var body: some View {
        ZStack {
            PageBackground()
            VSplitView {
                editorPane
                    .frame(minHeight: 330)

                if model.isConsoleVisible {
                    RunConsoleView(model: model)
                        .frame(minHeight: 130, idealHeight: TapeMetrics.consoleHeight, maxHeight: 360)
                }
            }
        }
        .navigationTitle(workflow.name)
        .onChange(of: model.activeStepID) { _, stepID in
            guard let stepID else { return }
            model.selectedStepID = stepID
        }
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            workflowHeader
            Divider()
            timeline
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.7))
    }

    private var workflowHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(workflow.accent.color.opacity(0.14))
                    Image(systemName: "recordingtape")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(workflow.accent.color)
                }
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    TextField("Tape name", text: $workflow.name)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                        .accessibilityLabel("Tape name")
                    TextField("Describe what this tape accomplishes", text: $workflow.summary, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1...2)
                        .accessibilityLabel("Tape description")
                }

                Spacer(minLength: 10)

                StatusPill(
                    title: model.runPhase.title,
                    icon: model.runPhase.systemImage,
                    tint: model.runPhase.tint
                )
            }

            HStack(spacing: 8) {
                Label("\(workflow.enabledStepCount) of \(workflow.steps.count) steps active", systemImage: "list.bullet.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                    .frame(height: 13)
                Label("Edited \(workflow.updatedAt, style: .relative)", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label("Manual start only", systemImage: "hand.raised.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .help("MacTape never runs a saved workflow automatically")
            }
        }
        .padding(.horizontal, TapeMetrics.pagePadding)
        .padding(.vertical, 17)
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Timeline")
                                .font(.headline)
                            Text("Select a step to edit its selector and safety settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        AddStepMenu { kind in
                            model.addStep(kind: kind, after: model.selectedStepID)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .padding(.bottom, 5)

                    if workflow.steps.isEmpty {
                        EmptyStateView(
                            icon: "list.bullet.clipboard",
                            title: "This tape has no steps",
                            message: "Add a visible action, a wait condition, or a verification step.",
                            buttonTitle: "Add First Step"
                        ) {
                            model.addStep(kind: .openApp)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(workflow.steps.indices), id: \.self) { index in
                            StepCardView(
                                step: $workflow.steps[index],
                                index: index,
                                isSelected: model.selectedStepID == workflow.steps[index].id,
                                isActive: model.activeStepID == workflow.steps[index].id,
                                showNote: model.showStepNotes,
                                select: {
                                    model.selectedStepID = workflow.steps[index].id
                                    model.isInspectorVisible = true
                                },
                                duplicate: {
                                    model.selectedStepID = workflow.steps[index].id
                                    model.duplicateSelectedStep()
                                },
                                delete: {
                                    model.selectedStepID = workflow.steps[index].id
                                    model.deleteSelectedStep()
                                },
                                moveUp: {
                                    model.selectedStepID = workflow.steps[index].id
                                    model.moveSelectedStep(by: -1)
                                },
                                moveDown: {
                                    model.selectedStepID = workflow.steps[index].id
                                    model.moveSelectedStep(by: 1)
                                },
                                canMoveUp: index > 0,
                                canMoveDown: index < workflow.steps.count - 1
                            )
                            .id(workflow.steps[index].id)
                        }

                        Button {
                            model.addStep(kind: .click, after: workflow.steps.last?.id)
                        } label: {
                            Label("Add another step", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityHint("Adds a click step at the end of this tape")
                    }
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, TapeMetrics.pagePadding)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.activeStepID) { _, stepID in
                guard let stepID else { return }
                withAnimation(.easeInOut(duration: 0.24)) {
                    proxy.scrollTo(stepID, anchor: .center)
                }
            }
        }
    }
}
