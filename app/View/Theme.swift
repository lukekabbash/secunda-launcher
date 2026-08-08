import SwiftUI

/// Design tokens. Views pick from these scales rather than inventing a
/// value, which is what keeps a fourth corner radius or a 12.5pt label from
/// creeping in one nudge at a time.
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
    /// Floor for capsule width, so short labels ("Play", "Install") read as
    /// the same control as their long neighbours instead of as nubs.
    static let controlMinWidth: CGFloat = 104

    /// Three steps, roughly 1.5x apart. `sm` is for thumbnails, `md` for
    /// rows and inline panels, `lg` for library cards.
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 18
    }

    /// Text sizes only. Icon glyphs (`Image(systemName:)`) are sized to the
    /// art around them and stay literal — forcing them onto a type scale
    /// makes symbols float in their frames.
    enum FontSize {
        /// Tracked-out eyebrows, badges, and metric captions.
        static let micro: CGFloat = 9
        /// Secondary labels, monospaced log text, card status lines.
        static let small: CGFloat = 11
        /// Default UI text: rows, controls, setting labels.
        static let body: CGFloat = 13
        /// Lead paragraphs and serif card titles.
        static let lead: CGFloat = 15
        /// Sheet titles.
        static let title: CGFloat = 22
        /// Numeric stats.
        static let display: CGFloat = 30
        /// Page and hero headlines.
        static let hero: CGFloat = 34
    }
}

// MARK: - Controls

/// Metrics, shape, and feedback shared by every capsule control, so a row
/// that mixes normal and destructive buttons stays on one baseline.
///
/// The caller's fill and stroke are drawn *here*, after the padding and the
/// height frame — a background applied before them wraps the bare text and
/// the label spills out of its own pill.
private struct CapsuleControl<Chrome: View>: ViewModifier {
    let isPressed: Bool
    let isEnabled: Bool
    /// Only the primary call to action goes semibold.
    var weight: Font.Weight = .medium
    @ViewBuilder var chrome: Chrome

    func body(content: Content) -> some View {
        content
            .font(.system(size: SecundaTheme.FontSize.body, weight: weight))
            // Filled SF Symbols (`play.fill`, `stop.fill`) read a full step
            // heavier than the text beside them at a matched point size.
            .imageScale(.small)
            .padding(.horizontal, 18)
            .frame(
                minWidth: SecundaTheme.controlMinWidth,
                minHeight: SecundaTheme.controlHeight,
                maxHeight: SecundaTheme.controlHeight
            )
            .background { chrome }
            .contentShape(Capsule())
            .scaleEffect(isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.1), value: isPressed)
    }
}

/// A generous, obviously-clickable capsule button — the default control for
/// actions. `prominent` is the primary call to action on a page.
///
/// The body lives in a nested `View` so `@State` and `@Environment` have
/// real view storage to hang off; a `ButtonStyle` is a value SwiftUI may
/// recreate, and property wrappers declared directly on it are unreliable.
struct SecundaActionButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, prominent: prominent)
    }

    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(prominent ? SecundaTheme.void : SecundaTheme.text)
                .modifier(CapsuleControl(
                    isPressed: configuration.isPressed,
                    isEnabled: isEnabled,
                    weight: prominent ? .semibold : .medium
                ) {
                    if prominent {
                        Capsule().fill(
                            LinearGradient(
                                colors: [SecundaTheme.moon, SecundaTheme.frost],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    } else {
                        ZStack {
                            Capsule().fill(Color.white.opacity(
                                configuration.isPressed ? 0.16 : (isHovering ? 0.11 : 0.06)
                            ))
                            Capsule().stroke(
                                isHovering ? SecundaTheme.frost.opacity(0.5) : SecundaTheme.hairline
                            )
                        }
                    }
                })
                .shadow(
                    color: SecundaTheme.frost.opacity(prominent ? prominentGlow : 0),
                    radius: 14,
                    y: 5
                )
                .animation(.easeOut(duration: 0.14), value: isHovering)
                .onHover { isHovering = isEnabled && $0 }
        }

        private var prominentGlow: Double {
            if configuration.isPressed { return 0.12 }
            return isHovering ? 0.34 : 0.25
        }
    }
}

/// Red-tinted capsule for stop/uninstall-class actions. Shares
/// `CapsuleControlChrome`, so mixed rows stay uniform.
struct SecundaDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(isHovering ? Color.white : SecundaTheme.danger)
                .modifier(CapsuleControl(
                    isPressed: configuration.isPressed,
                    isEnabled: isEnabled
                ) {
                    ZStack {
                        Capsule().fill(
                            isHovering
                                ? SecundaTheme.danger.opacity(configuration.isPressed ? 0.85 : 0.75)
                                : SecundaTheme.danger.opacity(0.10)
                        )
                        Capsule().stroke(SecundaTheme.danger.opacity(isHovering ? 0.9 : 0.45))
                    }
                })
                .animation(.easeOut(duration: 0.14), value: isHovering)
                .onHover { isHovering = isEnabled && $0 }
        }
    }
}

/// Circular icon-only button with a hover halo (sidebar gear, overflow menus).
struct SecundaIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
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
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.easeOut(duration: 0.14), value: isHovering)
                .onHover { isHovering = isEnabled && $0 }
        }
    }
}
