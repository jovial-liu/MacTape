import SwiftUI

struct PermissionOnboardingView: View {
    @ObservedObject var model: AppModel
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            Group {
                if page == 0 {
                    introduction
                } else {
                    permissions
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 700, height: 540)
        .background(PageBackground())
        .interactiveDismissDisabled(false)
        .onAppear(perform: model.refreshPermissions)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            TapeLogoView(size: 30)
            Text("Set up MacTape")
                .font(.headline)
            Spacer()
            HStack(spacing: 6) {
                Capsule()
                    .fill(page == 0 ? Color.indigo : Color.secondary.opacity(0.2))
                    .frame(width: page == 0 ? 22 : 7, height: 7)
                Capsule()
                    .fill(page == 1 ? Color.indigo : Color.secondary.opacity(0.2))
                    .frame(width: page == 1 ? 22 : 7, height: 7)
            }
            .animation(.easeInOut(duration: 0.2), value: page)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Setup step \(page + 1) of 2")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var introduction: some View {
        HStack(spacing: 38) {
            VStack(alignment: .leading, spacing: 18) {
                StatusPill(title: "LOCAL-FIRST AUTOMATION", icon: "lock.fill", tint: .indigo)
                Text("You stay in control of every tape.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text("MacTape records only after you press Record, stores workflows on this Mac, and keeps execution visible in a live console.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 11) {
                    OnboardingPromise(icon: "eye.fill", title: "Visible", detail: "Recording and running always have a persistent status.")
                    OnboardingPromise(icon: "slider.horizontal.3", title: "Reviewable", detail: "Disable or edit any step before it runs.")
                    OnboardingPromise(icon: "network.slash", title: "Offline", detail: "No account, sync service, or telemetry is required.")
                }
            }
            .frame(maxWidth: 390, alignment: .leading)

            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.1))
                    .frame(width: 180, height: 180)
                Image(systemName: "hand.raised.app.fill")
                    .font(.system(size: 94, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(colors: [.indigo, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)
        }
        .padding(38)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Choose what MacTape may access")
                    .font(.title2.weight(.semibold))
                Text("Grant only the capabilities your tapes need. Optional permissions can be enabled later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 9) {
                ForEach(AutomationPermission.allCases) { permission in
                    PermissionRow(
                        permission: permission,
                        state: model.permissionStates[permission] ?? .unknown,
                        request: { model.requestPermission(permission) },
                        openSettings: { model.openPermissionSettings(permission) }
                    )
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("macOS controls these permissions. MacTape cannot grant them silently, and removing access in System Settings takes effect immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(30)
    }

    private var footer: some View {
        HStack {
            Button("Not Now") {
                model.completePermissionOnboarding()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            if page > 0 {
                Button("Back") {
                    withAnimation { page = 0 }
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            }

            Button(page == 0 ? "Continue" : "Done") {
                if page == 0 {
                    withAnimation { page = 1 }
                } else {
                    model.completePermissionOnboarding()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

private struct OnboardingPromise: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.indigo)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionRow: View {
    let permission: AutomationPermission
    let state: PermissionState
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(state == .granted ? Color.green.opacity(0.11) : Color.indigo.opacity(0.09))
                Image(systemName: permission.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(state == .granted ? .green : .indigo)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(permission.title)
                        .font(.subheadline.weight(.semibold))
                    Text(permission.isRequired ? "REQUIRED" : "OPTIONAL")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(permission.isRequired ? .orange : .secondary)
                }
                Text(permission.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            if state == .granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Button(state == .unknown ? "Check" : "Open Settings") {
                    if state == .unknown { request() } else { openSettings() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("\(state == .unknown ? "Check" : "Open settings for") \(permission.title)")
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.primary.opacity(0.07))
        }
        .accessibilityElement(children: .contain)
    }
}
