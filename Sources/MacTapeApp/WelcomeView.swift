import SwiftUI

struct WelcomeView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            PageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    howItWorks
                    HStack(alignment: .top, spacing: 16) {
                        recentCard
                        privacyCard
                    }
                }
                .frame(maxWidth: 980)
                .padding(TapeMetrics.pagePadding)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Welcome")
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    TapeLogoView(size: 48)
                    Text("MacTape")
                        .font(.title2.weight(.semibold))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Record once.\nReplay with confidence.")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .tracking(-1.2)
                    Text("Turn a Mac workflow into transparent, editable steps. Dry-run it, inspect every action, then decide when it is safe to run.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 620, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Button {
                        model.createBlankWorkflow()
                    } label: {
                        Label("New Tape", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityHint("Creates an editable workflow without running it")

                    Button {
                        model.selection = .templates
                    } label: {
                        Label("Browse Templates", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            Spacer(minLength: 10)

            heroIllustration
                .frame(width: 230, height: 190)
        }
        .padding(30)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.indigo.opacity(0.13))
                        .frame(width: 220, height: 220)
                        .blur(radius: 26)
                        .offset(x: 50, y: -80)
                        .allowsHitTesting(false)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.primary.opacity(0.1))
        }
    }

    private var heroIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.indigo.opacity(0.09))
                .rotationEffect(.degrees(-4))
                .offset(x: -6, y: 3)

            VStack(spacing: 10) {
                illustrationStep(icon: "macwindow", title: "Open Finder", tint: .blue)
                illustrationStep(icon: "cursorarrow.click.2", title: "Select files", tint: .indigo)
                illustrationStep(icon: "checkmark.seal", title: "Verify result", tint: .green)
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("An example tape with Open Finder, Select files, and Verify result steps")
    }

    private func illustrationStep(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
        .padding(10)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "A workflow you can actually inspect", subtitle: "MacTape separates capture, review, and execution.")
            HStack(spacing: 14) {
                FeatureCard(
                    number: "01",
                    icon: "record.circle",
                    title: "Record",
                    detail: "Capture actions only while the red recorder is visibly active.",
                    tint: .red
                )
                FeatureCard(
                    number: "02",
                    icon: "slider.horizontal.3",
                    title: "Review",
                    detail: "Rename, disable, reorder, and dry-run every generated step.",
                    tint: .indigo
                )
                FeatureCard(
                    number: "03",
                    icon: "play.circle",
                    title: "Run",
                    detail: "Follow live progress and stop safely at any time.",
                    tint: .green
                )
            }
        }
    }

    @ViewBuilder
    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Recent Tape")
            if let workflow = model.workflows.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                Button {
                    model.selection = .workflow(workflow.id)
                    model.selectedStepID = workflow.steps.first?.id
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "recordingtape")
                            .font(.title2)
                            .foregroundStyle(workflow.accent.color)
                            .frame(width: 42, height: 42)
                            .background(workflow.accent.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workflow.name)
                                .font(.headline)
                            Text("\(workflow.enabledStepCount) active steps · Edited \(workflow.updatedAt, style: .relative) ago")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open recent tape \(workflow.name)")
            } else {
                Text("Your saved tapes will appear here. Start from a blank tape or a built-in template.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tapeCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "Private by default")
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.mint)
                    .accessibilityHidden(true)
            }
            Text("Workflow files, selectors, and run logs stay on this Mac. Permissions are requested individually and can be revoked in System Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Review Permissions") {
                model.showsPermissionOnboarding = true
            }
            .buttonStyle(.link)
            .accessibilityHint("Opens the permission setup assistant")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tapeCard()
    }
}

private struct FeatureCard: View {
    let number: String
    let icon: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
                Spacer()
                Text(number)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tapeCard()
        .accessibilityElement(children: .combine)
    }
}
