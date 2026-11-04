import SwiftUI

enum Theme {
    // MARK: Background

    static let backgroundTop = Color(hex: 0x0A0F1A)
    static let backgroundBottom = Color(hex: 0x141A29)
    static let background = LinearGradient(
        colors: [backgroundTop, backgroundBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: Accents and state

    static let accent = Color(hex: 0x5CC7FF)
    static let green = Color(hex: 0x5CD98F)
    static let orange = Color(hex: 0xFFAA4D)
    static let red = Color(hex: 0xFF6E6E)
    static let purple = Color(hex: 0xAD8CFF)
    static let teal = Color(hex: 0x4FD1C5)

    // MARK: Text

    static let textPrimary = Color(hex: 0xF5F7FA)
    static let textSecondary = Color(hex: 0xEBF0FF).opacity(0.55)
    static let textFaint = Color(hex: 0xEBF0FF).opacity(0.32)

    // MARK: Glass

    static let glassShadow = Color.black.opacity(0.26)
    static let glassRim = LinearGradient(
        colors: [
            .white.opacity(0.50),
            .white.opacity(0.10),
            .white.opacity(0.03),
            .white.opacity(0.20)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Metrics

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 24
        static let tile: CGFloat = 22
        static let control: CGFloat = 18
        static let capsule: CGFloat = 999
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
