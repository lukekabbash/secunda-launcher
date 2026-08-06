import SwiftUI

struct SecundaBackdrop: View {
    private let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = [
        (0.08, 0.16, 1.2, 0.55), (0.16, 0.72, 1.0, 0.35), (0.23, 0.31, 1.6, 0.62),
        (0.34, 0.12, 0.9, 0.42), (0.41, 0.82, 1.4, 0.50), (0.49, 0.43, 0.8, 0.34),
        (0.57, 0.20, 1.1, 0.55), (0.64, 0.69, 1.7, 0.48), (0.71, 0.37, 0.9, 0.40),
        (0.79, 0.13, 1.4, 0.58), (0.86, 0.80, 1.1, 0.36), (0.93, 0.46, 1.5, 0.52),
        (0.12, 0.48, 0.7, 0.28), (0.29, 0.61, 1.0, 0.44), (0.54, 0.91, 0.8, 0.30),
        (0.75, 0.57, 0.7, 0.34), (0.89, 0.24, 0.9, 0.38)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [SecundaTheme.void, SecundaTheme.midnight, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [SecundaTheme.aurora.opacity(0.16), .clear],
                    center: UnitPoint(x: 0.74, y: 0.18),
                    startRadius: 0,
                    endRadius: geometry.size.width * 0.52
                )

                ForEach(Array(stars.enumerated()), id: \.offset) { _, star in
                    Circle()
                        .fill(SecundaTheme.moon.opacity(star.opacity))
                        .frame(width: star.size, height: star.size)
                        .position(
                            x: geometry.size.width * star.x,
                            y: geometry.size.height * star.y
                        )
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [SecundaTheme.moon.opacity(0.32), SecundaTheme.frost.opacity(0.07), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 220
                        )
                    )
                    .frame(width: 440, height: 440)
                    .offset(x: geometry.size.width * 0.34, y: -geometry.size.height * 0.34)
                    .blur(radius: 4)

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.34)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct MoonMark: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle()
                .stroke(SecundaTheme.moon.opacity(0.72), lineWidth: 1)
            Circle()
                .fill(SecundaTheme.moon)
                .padding(size * 0.26)
                .shadow(color: SecundaTheme.frost.opacity(0.7), radius: 10)
            Circle()
                .fill(SecundaTheme.midnight)
                .frame(width: size * 0.42, height: size * 0.42)
                .offset(x: size * 0.10, y: -size * 0.07)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
