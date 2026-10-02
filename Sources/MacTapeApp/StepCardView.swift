import SwiftUI

struct StepCardView: View {
    @Binding var step: EditableStep
    let index: Int
    let isSelected: Bool
    let isActive: Bool
    let showNote: Bool
    let select: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            timelineMarker

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(step.kind.tint.opacity(0.12))
                        Image(systemName: step.kind.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(step.kind.tint)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title.isEmpty ? step.kind.title : step.title)
                            .font(.headline)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(step.kind.title)
                            if let summary = step.configuration.compactSummary {
                                Text("·")
                                Text(summary)
                                    .lineLimit(1)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if isActive {
                        StatusPill(title: "Running", icon: "play.fill", tint: .blue)
                    }

                    Toggle("Enable step", isOn: $step.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help(step.isEnabled ? "Disable this step" : "Enable this step")
                        .accessibilityLabel("\(step.isEnabled ? "Disable" : "Enable") step \(index + 1)")
                }

                if showNote, !step.note.isEmpty {
                    Text(step.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: TapeMetrics.cornerRadius, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.thinMaterial))
            }
            .overlay {
                RoundedRectangle(cornerRadius: TapeMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? step.kind.tint.opacity(0.65) : .primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .shadow(color: isSelected ? step.kind.tint.opacity(0.11) : .clear, radius: 12, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: TapeMetrics.cornerRadius, style: .continuous))
            .onTapGesture(perform: select)
            .opacity(step.isEnabled ? 1 : 0.56)
            .contextMenu {
                Button(action: duplicate) {
                    Label("Duplicate Step", systemImage: "plus.square.on.square")
                }
                Divider()
                Button(action: moveUp) {
                    Label("Move Up", systemImage: "arrow.up")
                }
                .disabled(!canMoveUp)
                Button(action: moveDown) {
                    Label("Move Down", systemImage: "arrow.down")
                }
                .disabled(!canMoveDown)
                Divider()
                Button(role: .destructive, action: delete) {
                    Label("Delete Step", systemImage: "trash")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Step \(index + 1), \(step.title), \(step.isEnabled ? "enabled" : "disabled")")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityAction(named: "Select", select)
        }
    }

    private var timelineMarker: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.blue : (isSelected ? step.kind.tint : Color.secondary.opacity(0.16)))
                if isActive {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index + 1)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                }
            }
            .frame(width: 25, height: 25)
            .accessibilityHidden(true)
        }
        .padding(.top, 15)
    }
}

struct AddStepMenu: View {
    let add: (EditableStep.ActionKind) -> Void

    var body: some View {
        Menu {
            ForEach(EditableStep.ActionKind.allCases) { kind in
                Button {
                    add(kind)
                } label: {
                    Label(kind.title, systemImage: kind.icon)
                }
            }
        } label: {
            Label("Add Step", systemImage: "plus")
        }
        .accessibilityLabel("Add workflow step")
    }
}
