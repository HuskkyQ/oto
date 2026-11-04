import SwiftUI

/// C-20 — 6 pt track with a gradient fill and a marker at the start level.
struct SoCBar: View {
    let start: Int?
    let end: Int?

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(Fmt.percent(start))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent, Theme.green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width * fraction(end))

                    if start != nil {
                        Rectangle()
                            .fill(.white.opacity(0.7))
                            .frame(width: 1.5)
                            .offset(x: width * fraction(start))
                    }
                }
            }
            .frame(height: 6)

            Text(Fmt.percent(end))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("电量 \(Fmt.percent(start)) 到 \(Fmt.percent(end))")
    }

    private func fraction(_ value: Int?) -> CGFloat {
        CGFloat(min(max(Double(value ?? 0) / 100, 0), 1))
    }
}
