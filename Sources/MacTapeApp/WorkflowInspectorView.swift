import SwiftUI

struct WorkflowInspectorView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if let step = model.selectedStepBinding() {
                StepInspectorView(
                    step: step,
                    duplicate: model.duplicateSelectedStep,
                    delete: model.deleteSelectedStep
                )
            } else if let workflowID = model.selectedWorkflowID,
                      let workflow = model.workflowBinding(for: workflowID) {
                WorkflowDetailsInspector(workflow: workflow)
            } else {
                EmptyStateView(
                    icon: "sidebar.right",
                    title: "Nothing selected",
                    message: "Select a tape or timeline step to inspect it."
                )
            }
        }
        .frame(minWidth: 260, idealWidth: TapeMetrics.inspectorWidth)
        .background(.bar)
    }
}

private struct StepInspectorView: View {
    @Binding var step: EditableStep
    let duplicate: () -> Void
    let delete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                basics
                actionConfiguration
                safety
                actions
            }
            .padding(18)
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(step.kind.tint.opacity(0.13))
                Image(systemName: step.kind.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(step.kind.tint)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Step Inspector")
                    .font(.headline)
                Text(step.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Enabled", isOn: $step.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Step enabled")
        }
    }

    private var basics: some View {
        InspectorSection(title: "General") {
            LabeledContent("Action") {
                Picker("Action", selection: $step.kind) {
                    ForEach(EditableStep.ActionKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.icon)
                            .tag(kind)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 170)
                .accessibilityLabel("Action type")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Step name", text: $step.title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Step name")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Explain intent or safety context", text: $step.note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                    .accessibilityLabel("Step note")
            }
        }
    }

    @ViewBuilder
    private var actionConfiguration: some View {
        InspectorSection(title: "Configuration") {
            switch step.kind {
            case .openApp:
                InspectorTextField(label: "Application", placeholder: "Finder", text: $step.configuration.application)

            case .click:
                selectorField(prompt: "Button named Continue")

            case .typeText:
                selectorField(prompt: "Search field")
                VStack(alignment: .leading, spacing: 5) {
                    Text("Text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $step.configuration.text)
                        .font(.body.monospaced())
                        .frame(minHeight: 62)
                        .padding(5)
                        .background(.background, in: RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(.separator.opacity(0.6))
                        }
                        .accessibilityLabel("Text to type")
                }
                Toggle("Hide value in run logs", isOn: $step.configuration.redactInLogs)
                    .font(.subheadline)

            case .shortcut:
                InspectorTextField(label: "Shortcut", placeholder: "⌘⇧P", text: $step.configuration.shortcut)

            case .wait:
                LabeledContent("Duration") {
                    HStack(spacing: 5) {
                        TextField("Seconds", value: $step.configuration.seconds, format: .number.precision(.fractionLength(0...1)))
                            .frame(width: 58)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Wait duration in seconds")
                        Text("sec")
                            .foregroundStyle(.secondary)
                    }
                }

            case .waitForElement, .assertElement:
                selectorField(prompt: "Visible label or accessibility role")
                timeoutField

            case .runShell:
                VStack(alignment: .leading, spacing: 5) {
                    Text("Command")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $step.configuration.command)
                        .font(.body.monospaced())
                        .frame(minHeight: 78)
                        .padding(5)
                        .background(.background, in: RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(.separator.opacity(0.6))
                        }
                        .accessibilityLabel("Shell command")
                }
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.shield")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Commands are shown in full during Dry Run and require live-run confirmation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                timeoutField
            }
        }
    }

    private var safety: some View {
        InspectorSection(title: "Failure behavior") {
            Toggle("Continue if this step fails", isOn: $step.configuration.continueOnFailure)
                .font(.subheadline)
            if step.configuration.continueOnFailure {
                Text("Use sparingly: later steps may depend on this result.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("Recommended. The tape stops here and leaves later actions untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button(action: duplicate) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Spacer()
            Button(role: .destructive, action: delete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func selectorField(prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Element selector")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(prompt, text: $step.configuration.selector)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Element selector")
            Text("Prefer visible labels and roles over screen coordinates.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var timeoutField: some View {
        LabeledContent("Timeout") {
            HStack(spacing: 5) {
                TextField("Seconds", value: $step.configuration.timeout, format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 58)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Timeout in seconds")
                Text("sec")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WorkflowDetailsInspector: View {
    @Binding var workflow: EditableWorkflow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Tape Inspector")
                        .font(.headline)
                    Spacer()
                    StatusPill(title: "Manual", icon: "hand.raised.fill", tint: .secondary)
                }

                InspectorSection(title: "Appearance") {
                    LabeledContent("Color") {
                        Picker("Color", selection: $workflow.accent) {
                            ForEach(TapeAccent.allCases) { accent in
                                Text(accent.rawValue.capitalized).tag(accent)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 150)
                    }
                }

                InspectorSection(title: "Variables") {
                    if workflow.variables.isEmpty {
                        Text("Variables make templates reusable without hiding their inputs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach($workflow.variables) { $variable in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                TextField("Name", text: $variable.name)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Variable name")
                                Button {
                                    workflow.variables.removeAll(where: { $0.id == variable.id })
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Remove variable \(variable.name)")
                            }
                            TextField("Value", text: $variable.value)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())
                                .accessibilityLabel("Value for \(variable.name)")
                        }
                    }

                    Button {
                        workflow.variables.append(.init(name: "variable", value: ""))
                    } label: {
                        Label("Add Variable", systemImage: "plus")
                    }
                }

                InspectorSection(title: "Metadata") {
                    LabeledContent("Created", value: workflow.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Updated", value: workflow.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Steps", value: "\(workflow.steps.count)")
                }
            }
            .padding(18)
        }
    }
}

private struct InspectorTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
        }
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
