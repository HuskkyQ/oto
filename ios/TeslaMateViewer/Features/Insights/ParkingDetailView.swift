import SwiftUI

/// 06 — one parking session in full.
///
/// Everything here comes from the list row's own payload: `/parking` already carries the range,
/// battery, temperature and state split per session, so a detail request would fetch nothing new.
struct ParkingDetailView: View {
    let session: ParkingSession

    @EnvironmentObject private var chrome: TabBarChrome
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenScaffold(title: "停车详情", backAction: { dismiss() }) {
            VStack(spacing: Theme.Spacing.l) {
                headline
                energy
                vehicle

                Text("「每小时损失」= 续航损失 ÷ 停车小时数，保留两位小数；不足 1 小时按实际时长计算。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.l)
            }
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .toolbar(.hidden, for: .navigationBar)
        .interactiveBackEnabled()
        .contentMargins(.bottom, 0, for: .scrollContent)
        .onAppear { chrome.hide() }
        .onDisappear { chrome.show() }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("\(Fmt.rangeLabel(from: session.startDate, to: session.endDate)) · \(session.title)")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.durationParts(minutes: session.durationMin).value)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Text(Fmt.durationParts(minutes: session.durationMin).unit)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            ProportionBar(slices: ParkingLegend.slices(session.stateMinutes), showsLegend: false)
                .padding(.top, Theme.Spacing.xs)

            ParkingStateLegend(session: session)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, Theme.Spacing.l)
    }

    private var energy: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("能耗")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            row("消耗电量", session.energyKwh.map { String(format: "%.2f kWh", $0) } ?? "—")
            row("续航损失", Fmt.km(session.rangeLossKm))
            row("每小时损失", session.rangeLossPerHourKm.map { String(format: "%.2f km/h", $0) } ?? "—")
            row("电量损耗", batteryDrop)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, Theme.Spacing.l)
    }

    private var vehicle: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("车辆")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            row("电量变化", transition(session.startBatteryLevel, session.endBatteryLevel, "%"))
            row("续航变化", transition(session.startRangeKm, session.endRangeKm, " km", decimals: 0))
            row("里程", session.odometerKm.map { "\(Int($0.rounded()).formatted()) km" } ?? "—")
            row("车外温度", Fmt.temp(session.outsideTempAvg))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, Theme.Spacing.l)
    }

    private var batteryDrop: String {
        guard let start = session.startBatteryLevel, let end = session.endBatteryLevel else { return "—" }
        let drop = start - end
        // A parked car can gain a point from a warm pack; say so rather than showing "-1%".
        return drop >= 0 ? "\(drop)%" : "回充 \(abs(drop))%"
    }

    private func transition(
        _ start: Int?,
        _ end: Int?,
        _ unit: String,
        decimals: Int = 0
    ) -> String {
        guard let start, let end else { return "—" }
        let format = "%.\(decimals)f"
        return "\(String(format: format, Double(start)))\(unit) → \(String(format: format, Double(end)))\(unit)"
    }

    private func transition(_ start: Double?, _ end: Double?, _ unit: String, decimals: Int = 0) -> String {
        guard let start, let end else { return "—" }
        let format = "%.\(decimals)f"
        return "\(String(format: format, start))\(unit) → \(String(format: format, end))\(unit)"
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.l) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.footnote.weight(.medium).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
