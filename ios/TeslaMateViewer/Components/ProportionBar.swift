import SwiftUI

/// C-40 — one share of a whole.
struct ProportionSlice: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}

/// C-40 — a stacked share bar with an optional legend and one trailing note.
///
/// For two or three parts ("asleep vs online"). At four parts and beyond this stops being
/// readable — use `StatusTimeline` (C-39) instead.
struct ProportionBar: View {
    let slices: [ProportionSlice]
    var showsLegend = true
    /// Right-aligned under the legend: average power, totals, anything the bar itself cannot say.
    var note: String?

    private var total: Double {
        max(slices.reduce(0) { $0 + max($1.value, 0) }, 0.001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { proxy in
                let gaps = CGFloat(max(slices.count - 1, 0)) * 2
                let available = max(proxy.size.width - gaps, 0)

                HStack(spacing: 2) {
                    ForEach(slices) { slice in
                        Rectangle()
                            .fill(slice.color)
                            .frame(width: max(2, available * CGFloat(max(slice.value, 0) / total)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .frame(height: 8)

            if showsLegend {
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(slices) { slice in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(slice.color)
                                .frame(width: 6, height: 6)

                            Text(slice.label)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    Spacer(minLength: 0)

                    if let note {
                        Text(note)
                            .foregroundStyle(Theme.textFaint)
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 10.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("占比")
        .accessibilityValue(
            slices
                .map { "\($0.label) \(Int(($0.value / total * 100).rounded()))%" }
                .joined(separator: "，")
        )
    }
}
