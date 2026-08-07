import SwiftUI

enum SecundaTheme {
    static let void = Color(red: 0.018, green: 0.025, blue: 0.045)
    static let midnight = Color(red: 0.035, green: 0.052, blue: 0.085)
    static let slate = Color(red: 0.105, green: 0.125, blue: 0.16)
    static let moon = Color(red: 0.82, green: 0.87, blue: 0.91)
    /// Accent: muted sea-glass teal (replaced the old pale baby-blue).
    static let frost = Color(red: 0.45, green: 0.64, blue: 0.60)
    static let aurora = Color(red: 0.36, green: 0.62, blue: 0.65)
    static let ember = Color(red: 0.78, green: 0.60, blue: 0.32)
    /// Destructive actions: stop, uninstall, force-kill.
    static let danger = Color(red: 0.83, green: 0.38, blue: 0.34)
    static let text = Color(red: 0.92, green: 0.94, blue: 0.96)
    static let secondaryText = Color(red: 0.62, green: 0.67, blue: 0.73)
    static let hairline = Color.white.opacity(0.10)
    /// Every capsule control in an action row shares this height.
    static let controlHeight: CGFloat = 40

    static let panel = LinearGradient(
        colors: [Color.white.opacity(0.075), Color.white.opacity(0.035)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct SecundaPanel: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(SecundaTheme.panel)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(SecundaTheme.hairline, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func secundaPanel(padding: CGFloat = 20) -> some View {
        modifier(SecundaPanel(padding: padding))
    }
}

/// Flat content section: an uppercase heading over a hairline, no box.
/// The restrained alternative to nesting panels.
struct FlatSection<Content: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2.0)
                        .foregroundStyle(SecundaTheme.frost)
                    Spacer()
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(SecundaTheme.secondaryText)
                    }
                }
                Rectangle()
                    .fill(SecundaTheme.hairline)
                    .frame(height: 1)
            }
            content
        }
    }
}

/// A generous, obviously-clickable text button with a hover state — the
/// default control for secondary actions.
struct SecundaActionButtonStyle: ButtonStyle {
    var prominent = false

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(prominent ? SecundaTheme.void : SecundaTheme.text)
            .padding(.horizontal, 16)
            .frame(height: SecundaTheme.controlHeight)
            .background {
                if prominent {
                    Capsule().fill(SecundaTheme.moon)
                } else {
                    Capsule().fill(Color.white.opacity(
                        configuration.isPressed ? 0.16 : (isHovering ? 0.11 : 0.06)
                    ))
                }
            }
            .overlay {
                if !prominent {
                    Capsule().stroke(
                        isHovering ? SecundaTheme.frost.opacity(0.5) : SecundaTheme.hairline
                    )
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { isHovering = $0 }
    }
}

/// Red-tinted capsule for stop/uninstall-class actions. Same metrics as
/// SecundaActionButtonStyle so mixed rows stay uniform.
struct SecundaDestructiveButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(isHovering ? Color.white : SecundaTheme.danger)
            .padding(.horizontal, 16)
            .frame(height: SecundaTheme.controlHeight)
            .background {
                Capsule().fill(
                    isHovering
                        ? SecundaTheme.danger.opacity(configuration.isPressed ? 0.85 : 0.75)
                        : SecundaTheme.danger.opacity(0.10)
                )
            }
            .overlay {
                Capsule().stroke(SecundaTheme.danger.opacity(isHovering ? 0.9 : 0.45))
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

/// Circular icon-only button with a hover halo (sidebar gear, overflow menus).
struct SecundaIconButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isHovering ? SecundaTheme.text : SecundaTheme.secondaryText)
            .frame(width: SecundaTheme.controlHeight, height: SecundaTheme.controlHeight)
            .background {
                Circle().fill(Color.white.opacity(
                    configuration.isPressed ? 0.15 : (isHovering ? 0.09 : 0)
                ))
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = $0 }
    }
}
