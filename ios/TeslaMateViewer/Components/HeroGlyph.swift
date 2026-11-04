import SwiftUI

/// C-38 — 78 pt accent-tinted rounded square holding one icon.
struct HeroGlyph: View {
    let systemImage: String

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Theme.accent.opacity(0.14))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.30), lineWidth: 1)
            }
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 78, height: 78)
            .accessibilityHidden(true)
    }
}
