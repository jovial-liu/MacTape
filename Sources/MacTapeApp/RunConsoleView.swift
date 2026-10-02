import SwiftUI

struct RunConsoleView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            consoleHeader
            Divider()
            logBody
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run console")
    }

    private var consoleHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Run Console")
                .font(.subheadline.weight(.semibold))

            StatusPill(
                title: model.runPhase.title,
                icon: model.runPhase.systemImage,
                tint: model.runPhase.tint
            )

            if model.runPhase.isActive, model.runPhase != .recording {
                ProgressView(value: model.runProgress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 150)
                    .accessibilityLabel("Workflow progress")
                    .accessibilityValue(Text(model.runProgress, format: .percent))
            }

            Spacer()

            if model.runPhase.isActive {
                Button(action: model.stop) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Stop safely")
                .accessibilityLabel("Stop current activity")
            }

            Menu {
                Button(action: model.clearConsole) {
                    Label("Clear Console", systemImage: "trash")
                }
                .disabled(model.consoleEntries.isEmpty)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .accessibilityLabel("Console options")

            Button {
                model.isConsoleVisible = false
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .help("Hide console")
            .accessibilityLabel("Hide run console")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if model.consoleEntries.isEmpty {
                        HStack(spacing: 9) {
                            Image(systemName: "text.alignleft")
                                .foregroundStyle(.tertiary)
                            Text("Run events will appear here. Start with Dry Run to preview every action.")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(.vertical, 12)
                    } else {
                        ForEach(model.consoleEntries) { entry in
                            Button {
                                model.revealConsoleEntry(entry)
                            } label: {
                                RunLogRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .disabled(entry.stepID == nil)
                            .id(entry.id)
                        }
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.consoleEntries.count) { _, _ in
                guard let lastID = model.consoleEntries.last?.id else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }
}

private struct RunLogRow: View {
    let entry: RunLogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.date, format: .dateTime.hour().minute().second())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 62, alignment: .leading)
            Image(systemName: entry.level.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(entry.level.tint)
                .frame(width: 12)
                .accessibilityHidden(true)
            Text(entry.message)
                .font(.caption.monospaced())
                .foregroundStyle(entry.level == .error ? Color.red : Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.level.rawValue), \(entry.message)")
    }
}
