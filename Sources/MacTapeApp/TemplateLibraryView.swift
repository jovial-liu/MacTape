import SwiftUI

struct TemplateLibraryView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""

    private var filteredTemplates: [WorkflowTemplate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.templates }
        return model.templates.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.summary.localizedCaseInsensitiveContains(query)
                || $0.useCase.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            PageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16)],
                        alignment: .leading,
                        spacing: 16
                    ) {
                        ForEach(filteredTemplates) { template in
                            TemplateCard(template: template) {
                                model.createWorkflow(from: template)
                            }
                        }
                    }

                    if filteredTemplates.isEmpty {
                        EmptyStateView(
                            icon: "magnifyingglass",
                            title: "No matching templates",
                            message: "Try a broader search, or start with a blank tape.",
                            buttonTitle: "Create Blank Tape"
                        ) {
                            model.createBlankWorkflow()
                        }
                        .frame(maxWidth: .infinity)
                    }

                    safetyNote
                }
                .frame(maxWidth: 1140)
                .padding(TapeMetrics.pagePadding)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Templates")
        .searchable(text: $searchText, prompt: "Search templates")
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Start with a tape you can trust")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Each template is editable, local, and created in an inactive state. Review it before the first run.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.createBlankWorkflow()
            } label: {
                Label("Blank Tape", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Creates a tape without running any actions")
        }
    }

    private var safetyNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title3)
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Templates never run automatically")
                    .font(.headline)
                Text("Using a template only creates an editable copy. MacTape will still show its actions, required permissions, and a dry-run preview before execution.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .tapeCard()
        .accessibilityElement(children: .combine)
    }
}

private struct TemplateCard: View {
    let template: WorkflowTemplate
    let useTemplate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(template.accent.color.opacity(0.13))
                    Image(systemName: template.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(template.accent.color)
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(width: 50, height: 50)
                .accessibilityHidden(true)

                Spacer()

                Text(template.useCase.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(template.accent.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(template.accent.color.opacity(0.1), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(template.name)
                    .font(.title3.weight(.semibold))
                Text(template.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 40, alignment: .top)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(template.steps.prefix(3).enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 9) {
                        Text("\(index + 1)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(template.accent.color)
                            .frame(width: 20, height: 20)
                            .background(template.accent.color.opacity(0.1), in: Circle())
                        Image(systemName: step.kind.icon)
                            .font(.caption)
                            .foregroundStyle(step.kind.tint)
                            .frame(width: 16)
                        Text(step.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                    }
                }
                if template.steps.count > 3 {
                    Text("+ \(template.steps.count - 3) more reviewable steps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 29)
                }
            }
            .padding(12)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Label("\(template.steps.count) steps", systemImage: "list.number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Use Template", action: useTemplate)
                    .buttonStyle(.borderedProminent)
                    .tint(template.accent.color)
                    .accessibilityLabel("Use \(template.name) template")
                    .accessibilityHint("Creates an inactive editable copy")
            }
        }
        .tapeCard(padding: 18, emphasized: true)
        .accessibilityElement(children: .contain)
    }
}
