import SwiftUI

/// C-41 — one column of a compact trend.
struct MiniBar: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    /// The column the page is about — this month, today. Draws brighter, not taller.
    var highlighted = false
}

/// C-41 — six or seven bars with no axis and no grid.
///
/// For "what is the shape of this?" at a glance. When the reader needs to compare exact values,
/// use `BarChart` (C-26) instead: this component deliberately has no scale.
struct MiniBars: View {
    let bars: [MiniBar]
    /// Announced by VoiceOver in place of the bars; also the visible footnote when set.
    var summary: String?
    var trailing: String?
    var height: CGFloat = 58

    private var peak: Double {
        max(bars.map(\.value).max() ?? 0, 0.001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(bars) { bar in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: bar.highlighted
                                        ? [Theme.accent.opacity(0.95), Theme.accent.opacity(0.30)]
                                        : [Theme.accent.opacity(0.55), Theme.accent.opacity(0.12)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: max(3, (height - 22) * CGFloat(max(bar.value, 0) / peak)))

                        Text(bar.label)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: height, alignment: .bottom)

            if summary != nil || trailing != nil {
                HStack {
                    if let summary {
                        Text(summary)
                            .foregroundStyle(Theme.textFaint)
                    }

                    Spacer(minLength: 0)

                    if let trailing {
                        Text(trailing)
                            .foregroundStyle(Theme.textFaint)
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 11))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary ?? "趋势")
        .accessibilityValue(
            bars
                .map { "\($0.label) \($0.value.formatted(.number.precision(.fractionLength(0...1))))" }
                .joined(separator: "，")
        )
    }
}
