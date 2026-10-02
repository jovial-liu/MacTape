import AppKit
import MacTapeCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            SafetySettings(model: model)
                .tabItem { Label("Safety", systemImage: "checkmark.shield") }
            PermissionSettings(model: model)
                .tabItem { Label("Permissions", systemImage: "hand.raised") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 430)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $model.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("App appearance")

                Toggle("Show notes on timeline cards", isOn: $model.showStepNotes)
                Toggle("Keep the run console open", isOn: $model.keepConsoleOpen)
            }

            Section("Feedback") {
                Toggle("Play a sound when a run finishes", isOn: $model.playCompletionSound)
            }

            Section("Workflow files") {
                LabeledContent("Storage", value: "Application Support/MacTape")
                Button("Show Workflow Folder") {
                    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    NSWorkspace.shared.open(support.appending(path: "MacTape", directoryHint: .isDirectory))
                }
                .accessibilityHint("Opens the local MacTape data folder in Finder")
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
}

private struct SafetySettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Before running") {
                Toggle("Confirm before every live run", isOn: $model.confirmBeforeLiveRun)
                LabeledContent("Recommended first step") {
                    StatusPill(title: "Dry Run", icon: "play.slash", tint: .orange)
                }
            }

            Section("Execution policy") {
                SafetyRule(icon: "eye.fill", title: "Visible execution", detail: "Every active step appears in the console and timeline.")
                SafetyRule(icon: "stop.circle.fill", title: "Safe stop", detail: "Stop prevents later steps from starting; it does not roll back completed work.")
                SafetyRule(icon: "terminal.fill", title: "Shell transparency", detail: "Commands remain visible in the editor and dry-run output.")
            }

            Section {
                Text("MacTape does not schedule or trigger workflows in the background. A run starts only from an explicit Run action.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
}

private struct PermissionSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("macOS permissions") {
                ForEach(AutomationPermission.allCases) { permission in
                    HStack(spacing: 10) {
                        Image(systemName: permission.icon)
                            .foregroundStyle(.indigo)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(permission.title)
                            Text(permission.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(
                            title: (model.permissionStates[permission] ?? .unknown).title,
                            icon: model.permissionStates[permission] == .granted ? "checkmark.circle.fill" : "circle.dashed",
                            tint: model.permissionStates[permission] == .granted ? .green : .secondary
                        )
                        Button("Settings") {
                            model.openPermissionSettings(permission)
                        }
                        .controlSize(.small)
                        .accessibilityLabel("Open \(permission.title) settings")
                    }
                }
            }

            Section {
                HStack {
                    Button("Refresh Status", action: model.refreshPermissions)
                    Button("Open Setup Assistant") {
                        model.showsPermissionOnboarding = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .onAppear(perform: model.refreshPermissions)
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 15) {
            TapeLogoView(size: 72)
            VStack(spacing: 4) {
                Text("MacTape")
                    .font(.title2.weight(.semibold))
                Text("Version \(MacTapeCore.productVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Record a Mac workflow, inspect every step, and replay it with a visible safety boundary.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 14) {
                Link("Source", destination: URL(string: "https://github.com/")!)
                Text("·").foregroundStyle(.tertiary)
                Text("Open source")
            }
            .font(.caption)
            Spacer().frame(height: 8)
            Label("No account · No telemetry · Local workflow files", systemImage: "lock.shield.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

private struct SafetyRule: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        LabeledContent {
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 290, alignment: .trailing)
        } label: {
            Label(title, systemImage: icon)
        }
        .accessibilityElement(children: .combine)
    }
}
