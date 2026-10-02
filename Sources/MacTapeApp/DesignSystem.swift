import SwiftUI

enum TapeMetrics {
    static let cornerRadius: CGFloat = 14
    static let compactCornerRadius: CGFloat = 9
    static let pagePadding: CGFloat = 24
    static let inspectorWidth: CGFloat = 300
    static let consoleHeight: CGFloat = 190
}

struct TapeCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var emphasized = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: TapeMetrics.cornerRadius, style: .continuous)
                    .fill(emphasized ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.thinMaterial))
            }
            .overlay {
                RoundedRectangle(cornerRadius: TapeMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(emphasized ? 0.13 : 0.08))
            }
    }
}

extension View {
    func tapeCard(padding: CGFloat = 16, emphasized: Bool = false) -> some View {
        modifier(TapeCardModifier(padding: padding, emphasized: emphasized))
    }
}

struct TapeLogoView: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.indigo, Color(red: 0.48, green: 0.27, blue: 0.96), Color.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "recordingtape")
                .font(.system(size: size * 0.54, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.monochrome)
        }
        .frame(width: size, height: size)
        .shadow(color: .indigo.opacity(0.22), radius: 10, y: 5)
        .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.11), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

struct KeyboardHint: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(.caption2.monospaced().weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel("Keyboard shortcut \(keys)")
    }
}

struct PageBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.indigo.opacity(colorScheme == .dark ? 0.12 : 0.055),
                    Color.clear,
                    Color.cyan.opacity(colorScheme == .dark ? 0.07 : 0.03),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(32)
        .accessibilityElement(children: .contain)
    }
}
