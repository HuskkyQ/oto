import SwiftUI

/// C-37 — label plus a 45 × 27 glass switch.
struct ToggleRow: View {
    let title: String
    var caption: String?
    @Binding var isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer(minLength: Theme.Spacing.s)

            Button {
                if reduceMotion {
                    isOn.toggle()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { isOn.toggle() }
                }
            } label: {
                Capsule()
                    .fill(isOn ? Theme.accent.opacity(0.85) : Color.white.opacity(0.12))
                    .frame(width: 45, height: 27)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 23, height: 23)
                            .padding(2)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "开启" : "关闭")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(minHeight: 56)
    }
}
