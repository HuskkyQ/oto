import SwiftUI

/// The track's time filter: four quick ranges and one custom window.
///
/// `onApply` receives the chosen range; the sheet never fetches. The 7 / 30 / 90 segments stay on
/// the page below it, so the filter is an addition to them, not a replacement.
struct HistoryFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onApply: (ClosedRange<Date>) -> Void

    @State private var start: Date
    @State private var end: Date
    @State private var activeQuick: Quick?
    /// The range the highlighted chip produced; editing either date clears the highlight.
    @State private var quickSnapshot: ClosedRange<Date>?

    enum Quick: String, CaseIterable, Identifiable {
        case today
        case threeDays
        case week
        case month

        var id: String { rawValue }

        var label: String {
            switch self {
            case .today: return "今日"
            case .threeDays: return "最近 3 天"
            case .week: return "最近一周"
            case .month: return "本月"
            }
        }

        var range: ClosedRange<Date> {
            let calendar = Calendar.current
            let now = Date()
            let today = calendar.startOfDay(for: now)

            switch self {
            case .today:
                return today...now
            case .threeDays:
                let from = calendar.date(byAdding: .day, value: -2, to: today) ?? today
                return from...now
            case .week:
                let from = calendar.date(byAdding: .day, value: -6, to: today) ?? today
                return from...now
            case .month:
                let from = calendar.dateInterval(of: .month, for: now)?.start ?? today
                return from...now
            }
        }
    }

    init(initial: (Date, Date), onApply: @escaping (ClosedRange<Date>) -> Void) {
        self.onApply = onApply
        _start = State(initialValue: initial.0)
        _end = State(initialValue: initial.1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack {
                Text("筛选条件")
                    .font(.headline)
                Spacer()
                Button("重置") { reset() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }

            Text("快速筛选")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textFaint)

            HStack(spacing: Theme.Spacing.s) {
                ForEach(Quick.allCases) { quick in
                    chip(quick)
                }
                Spacer(minLength: 0)
            }

            Text("自定义时间范围")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, Theme.Spacing.xs)

            SettingsGroup {
                pickerRow("开始", selection: $start, showsDivider: true)
                pickerRow("结束", selection: $end, showsDivider: false)
            }

            if end <= start {
                Text("结束时间要晚于开始时间。")
                    .font(.caption2)
                    .foregroundStyle(Theme.orange)
            }

            Spacer(minLength: 0)

            PrimaryButton(title: "应用筛选", isEnabled: end > start) {
                onApply(start...end)
                dismiss()
            }
        }
        .padding(20)
        // The app is Chinese-only; the system pickers would otherwise say "Oct 5, 2026".
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .onChange(of: start) {
            if start != quickSnapshot?.lowerBound { activeQuick = nil }
        }
        .onChange(of: end) {
            if end != quickSnapshot?.upperBound { activeQuick = nil }
        }
    }

    private func chip(_ quick: Quick) -> some View {
        let isSelected = activeQuick == quick

        return Button {
            let range = quick.range
            quickSnapshot = range
            start = range.lowerBound
            end = range.upperBound
            activeQuick = quick
        } label: {
            Text(quick.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Theme.backgroundTop : Theme.textPrimary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Theme.accent : Color.white.opacity(0.08),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func pickerRow(_ title: String, selection: Binding<Date>, showsDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.m) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: Theme.Spacing.s)

                DatePicker(
                    title,
                    selection: selection,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Theme.accent)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .frame(minHeight: 52)

            if showsDivider {
                Rectangle()
                    .fill(.white.opacity(0.07))
                    .frame(height: 0.5)
                    .padding(.leading, Theme.Spacing.l)
            }
        }
    }

    private func reset() {
        let now = Date()
        start = Calendar.current.startOfDay(for: now)
        end = now
        activeQuick = nil
    }
}
