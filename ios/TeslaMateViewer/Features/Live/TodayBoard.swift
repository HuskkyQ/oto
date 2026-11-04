import SwiftUI

/// 今日 — the day's totals over the 24-hour state band.
///
/// Every figure comes from `/stats?bucket=day` or `/states`; nothing is derived from a battery
/// difference. Energy has no endpoint yet, so the card does not claim one.
struct TodayBoard: View {
    let day: StatsBucket?
    let slices: [StatusSlice]
    let isLoading: Bool
    let error: String?
    let onOpenCalendar: () -> Void
    let onRetry: () -> Void

    @State private var showLegend = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    SectionTitle(title: "今日")
                    Text(Fmt.monthDayWeekday(Date()))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    iconButton("info.circle") { showLegend = true }
                        .accessibilityLabel("车辆状态说明")
                    iconButton("calendar") { onOpenCalendar() }
                        .accessibilityLabel("行程日历")
                }
            }

            if isLoading && day == nil {
                Skeleton(height: 120)
            } else {
                StatStrip(columns: [
                    ("\(day?.driveCount ?? 0) 次", "行程"),
                    (Fmt.km(day?.distanceKm), "里程"),
                    (Fmt.duration(minutes: day?.durationMin ?? 0), "行驶")
                ])

                if slices.isEmpty {
                    Text("今天还没有车辆状态记录")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    StatusTimeline(slices: slices, scaleMinutes: 24 * 60)
                    StatusLegend(slices: slices)
                }

                Text(error ?? "按本地时间统计今天；休眠占比高属于正常。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(error == nil ? Theme.textFaint : Theme.orange)

                if error != nil {
                    Button("重试", action: onRetry)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .card()
        .sheet(isPresented: $showLegend) {
            StateLegendSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.backgroundTop)
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.74))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// 月度里程 — six calendar months, the current one highlighted.
struct MonthMileageCard: View {
    let months: [StatsBucket]

    private var total: Double {
        months.reduce(0) { $0 + $1.distanceKm }
    }

    private var average: Double {
        months.isEmpty ? 0 : total / Double(months.count)
    }

    var body: some View {
        let lastIndex = months.count - 1

        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "月度里程")

            MiniBars(
                bars: months.enumerated().map { index, bucket in
                    MiniBar(
                        label: Fmt.monthLabel(bucket.bucket),
                        value: bucket.distanceKm,
                        highlighted: index == lastIndex
                    )
                },
                summary: "近 \(months.count) 个月",
                trailing: "\(Int(total.rounded()).formatted()) km · 月均 \(Int(average.rounded()).formatted()) km"
            )
        }
        .card()
    }
}

/// The six states, in the order they are explained — the band's own legend is too small to
/// carry a sentence per state.
struct StateLegendSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let entries: [(state: String, meaning: String)] = [
        ("online", "车辆已唤醒，未行驶也未充电"),
        ("driving", "有速度或挡位不在 P"),
        ("charging", "充电枪已连接且正在充电"),
        ("asleep", "车辆睡眠，数据停止更新"),
        ("updating", "正在安装软件更新"),
        ("unknown", "这段时间没有上报记录")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("车辆状态说明")
                .font(.headline)

            Text("时间轴按车辆上报的状态切分，两个状态之间不会重叠。")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 10) {
                ForEach(entries, id: \.state) { entry in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(statusColor(entry.state))
                            .frame(width: 10, height: 10)

                        Text(statusLabel(entry.state))
                            .font(.footnote.weight(.medium))
                            .frame(width: 52, alignment: .leading)

                        Text(entry.meaning)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)

                        Spacer(minLength: 0)
                    }
                }
            }

            Spacer(minLength: 0)

            PrimaryButton(title: "完成") { dismiss() }
        }
        .padding(20)
    }
}
