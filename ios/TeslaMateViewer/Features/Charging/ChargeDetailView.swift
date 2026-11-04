import SwiftUI

struct ChargeDetailView: View {
    let chargeId: Int

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var chrome: TabBarChrome
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ChargeDetailViewModel()

    var body: some View {
        ScreenScaffold(title: "充电详情", backAction: { dismiss() }) {
            VStack(spacing: Theme.Spacing.l) {
                if model.unauthorized {
                    AuthBanner()
                        .padding(.horizontal, Theme.Spacing.l)
                } else if let error = model.error {
                    ErrorBanner(message: error, cachedAt: model.cachedAt)
                        .padding(.horizontal, Theme.Spacing.l)
                }

                if let detail = model.detail {
                    summary(detail.charge)
                    charts(detail.samples)
                    facts(detail)
                } else if model.isLoading {
                    VStack(spacing: Theme.Spacing.l) {
                        Skeleton(height: 140)
                        Skeleton(height: 190)
                        Skeleton(height: 190)
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                }
            }
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .toolbar(.hidden, for: .navigationBar)
        .interactiveBackEnabled()
        // Full height: no floating bar on this page.
        .contentMargins(.bottom, 0, for: .scrollContent)
        .onAppear { chrome.hide() }
        .onDisappear { chrome.show() }
        .task {
            await model.load(client: settings.client, carId: settings.carId, chargeId: chargeId)
        }
    }

    // MARK: Summary

    private func summary(_ charge: ChargingSession) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(charge.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(Fmt.dateTime(charge.startDate))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xl) {
                stat(Fmt.kwh(charge.chargeEnergyAdded), "已充")
                stat(Fmt.duration(minutes: charge.durationMin), "时长")
                stat(charge.cost.map { "¥\(Fmt.money($0))" } ?? "费用未记录", "费用")
            }

            SoCBar(start: charge.startBatteryLevel, end: charge.endBatteryLevel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Charts

    @ViewBuilder
    private func charts(_ samples: [ChargeSample]) -> some View {
        let domain = xDomain(samples)

        VStack(spacing: Theme.Spacing.l) {
            if let domain {
                let powers = points(samples, \.chargerPower)
                if powers.count > 1 {
                    MetricChart(
                        title: "功率",
                        unit: "kW",
                        color: Theme.accent,
                        points: powers,
                        summary: maxSummary(powers, unit: "kW"),
                        xDomain: domain
                    )
                }

                let levels = points(samples, \.batteryLevel)
                if levels.count > 1 {
                    MetricChart(
                        title: "电量",
                        unit: "%",
                        color: Theme.green,
                        points: levels,
                        summary: levels.last.map { String(format: "%.0f%%", $0.value) } ?? "—",
                        xDomain: domain
                    )
                }

                let energies = points(samples, \.chargeEnergyAdded)
                if energies.count > 1 {
                    MetricChart(
                        title: "已充电量",
                        unit: "kWh",
                        color: Theme.purple,
                        points: energies,
                        summary: energies.last.map { String(format: "%.1f kWh", $0.value) } ?? "—",
                        xDomain: domain
                    )
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func xDomain(_ samples: [ChargeSample]) -> ClosedRange<Date>? {
        guard let first = samples.first?.date,
              let last = samples.last?.date,
              first < last
        else { return nil }
        return first...last
    }

    private func points(_ samples: [ChargeSample], _ keyPath: KeyPath<ChargeSample, Double?>) -> [MetricPoint] {
        samples.compactMap { sample in
            sample[keyPath: keyPath].map { MetricPoint(date: sample.date, value: $0) }
        }
    }

    private func points(_ samples: [ChargeSample], _ keyPath: KeyPath<ChargeSample, Int?>) -> [MetricPoint] {
        samples.compactMap { sample in
            sample[keyPath: keyPath].map { MetricPoint(date: sample.date, value: Double($0)) }
        }
    }

    private func maxSummary(_ points: [MetricPoint], unit: String) -> String {
        guard let max = points.map(\.value).max() else { return "—" }
        return String(format: "最高 %.0f %@", max, unit)
    }

    // MARK: Facts

    private func facts(_ detail: ChargeDetailResponse) -> some View {
        let charge = detail.charge
        let samples = detail.samples

        return VStack(spacing: Theme.Spacing.s) {
            DetailRow(title: "起始电量", value: Fmt.percent(charge.startBatteryLevel))
            DetailRow(title: "结束电量", value: Fmt.percent(charge.endBatteryLevel))
            DetailRow(title: "时长", value: Fmt.duration(minutes: charge.durationMin))
            DetailRow(title: "电压 / 电流", value: powerLine(samples))
            DetailRow(title: "连接器", value: connector(samples))
            DetailRow(title: "车外温度", value: Fmt.temp(charge.outsideTempAvg ?? samples.reversed().compactMap(\.outsideTemp).first))

            if let cost = charge.cost {
                DetailRow(title: "费用", value: "¥\(Fmt.money(cost))")
            }
        }
        .card()
        .padding(.horizontal, Theme.Spacing.l)
    }

    /// Voltage, current and phases come from the last sample that recorded each one.
    private func powerLine(_ samples: [ChargeSample]) -> String {
        let parts = [
            lastValue(samples, \.chargerVoltage).map { "\($0) V" },
            lastValue(samples, \.chargerActualCurrent).map { "\($0) A" },
            lastValue(samples, \.chargerPhases).map { "\($0) 相" }
        ].compactMap { $0 }

        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func connector(_ samples: [ChargeSample]) -> String {
        lastValue(samples, \.connChargeCable).flatMap(clean) ?? "—"
    }

    private func lastValue<T>(_ samples: [ChargeSample], _ keyPath: KeyPath<ChargeSample, T?>) -> T? {
        samples.reversed().compactMap { $0[keyPath: keyPath] }.first
    }

    /// The API reports unset fast-charger fields as the literal "<invalid>".
    private func clean(_ value: String) -> String? {
        value == "<invalid>" ? nil : value
    }
}
