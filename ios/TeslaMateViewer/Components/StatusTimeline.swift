import SwiftUI

/// C-39 — one slice of the state band. `minutes` is the slice's duration, which is also its weight.
struct StatusSlice: Identifiable {
    let id = UUID()
    let state: String
    let minutes: Int
}

/// C-39 — the 24-hour band of vehicle states, drawn to scale.
///
/// Colours follow `StateBadge`: driving is green, charging orange, updating purple. Online and
/// asleep are two weights of white — the band already says "awake" by being brighter, so a fifth
/// hue would only add noise. Unknown is the faintest, never blank: a gap would read as "no time
/// passed".
struct StatusTimeline: View {
    let slices: [StatusSlice]
    var showsAxis = true
    /// Fixes the scale — 1 440 for "today so far", so 09:00 fills a third of the band instead of
    /// the whole of it. `nil` scales to what is there.
    var scaleMinutes: Int?

    private var total: Int {
        max(scaleMinutes ?? slices.reduce(0) { $0 + max($1.minutes, 0) }, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let gaps = CGFloat(max(slices.count - 1, 0)) * 2
                let available = max(proxy.size.width - gaps, 0)

                ZStack(alignment: .leading) {
                    // The part of the scale with no slices yet stays a faint track, so a band
                    // read at noon does not look like a finished day.
                    if scaleMinutes != nil {
                        Capsule().fill(.white.opacity(0.05))
                    }

                    HStack(spacing: 2) {
                        ForEach(slices) { slice in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(statusColor(slice.state))
                                .frame(width: max(3, available * CGFloat(max(slice.minutes, 0)) / CGFloat(total)))
                        }
                    }
                }
            }
            .frame(height: 12)

            if showsAxis {
                HStack {
                    ForEach(["0", "6", "12", "18", "24"], id: \.self) { tick in
                        Text(tick)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textFaint)
                            .monospacedDigit()

                        if tick != "24" {
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("车辆状态时间轴")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        StatusLegend.totals(for: slices)
            .map { "\(statusLabel($0.state)) \(Fmt.duration(minutes: $0.minutes))" }
            .joined(separator: "，")
    }
}

/// Totals for one state across the band.
struct StatusTotal: Identifiable {
    let state: String
    let minutes: Int

    var id: String { state }
}

/// The legend under the band: one entry per state that actually appears, in first-seen order.
struct StatusLegend: View {
    let slices: [StatusSlice]

    var body: some View {
        // A wrapping grid rather than one row: a day can show six states, and six labels with
        // durations do not fit across 350 pt.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: Theme.Spacing.s, alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(StatusLegend.totals(for: slices)) { entry in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(statusColor(entry.state))
                        .frame(width: 8, height: 8)

                    Text(statusLabel(entry.state))
                        .foregroundStyle(Theme.textSecondary)

                    Text(Fmt.durationCompact(minutes: entry.minutes))
                        .foregroundStyle(Theme.textPrimary)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.system(size: 10.5))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Totals per state, in the order the states first appear in the band.
    static func totals(for slices: [StatusSlice]) -> [StatusTotal] {
        var order: [String] = []
        var totals: [String: Int] = [:]

        for slice in slices {
            if totals[slice.state] == nil { order.append(slice.state) }
            totals[slice.state, default: 0] += max(slice.minutes, 0)
        }

        return order.map { StatusTotal(state: $0, minutes: totals[$0] ?? 0) }
    }
}

func statusColor(_ state: String) -> Color {
    switch state {
    case "driving": return Theme.green
    case "charging": return Theme.orange
    case "updating": return Theme.purple
    case "online": return .white.opacity(0.45)
    case "asleep": return .white.opacity(0.18)
    default: return .white.opacity(0.06)
    }
}

/// Same wording as `StateBadge`, so the two never disagree on a screen.
func statusLabel(_ state: String) -> String {
    switch state {
    case "online": return "在线"
    case "asleep": return "休眠"
    case "offline": return "离线"
    case "charging": return "充电中"
    case "driving": return "行驶"
    case "updating": return "更新中"
    case "suspended": return "已暂停"
    default: return "未知"
    }
}
