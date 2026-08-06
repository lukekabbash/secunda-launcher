import SwiftUI

enum SecundaTheme {
    static let void = Color(red: 0.018, green: 0.025, blue: 0.045)
    static let midnight = Color(red: 0.035, green: 0.052, blue: 0.085)
    static let slate = Color(red: 0.105, green: 0.125, blue: 0.16)
    static let moon = Color(red: 0.82, green: 0.87, blue: 0.91)
    static let frost = Color(red: 0.55, green: 0.70, blue: 0.79)
    static let aurora = Color(red: 0.36, green: 0.62, blue: 0.65)
    static let ember = Color(red: 0.78, green: 0.60, blue: 0.32)
    static let text = Color(red: 0.92, green: 0.94, blue: 0.96)
    static let secondaryText = Color(red: 0.62, green: 0.67, blue: 0.73)
    static let hairline = Color.white.opacity(0.10)

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
