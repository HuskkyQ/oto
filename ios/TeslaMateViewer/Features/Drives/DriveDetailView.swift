import MapKit
import SwiftUI

struct DriveDetailView: View {
    let driveId: Int

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var chrome: TabBarChrome
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = DriveDetailViewModel()

    var body: some View {
        ScreenScaffold(title: "行程详情", backAction: { dismiss() }) {
            VStack(spacing: Theme.Spacing.l) {
                if model.unauthorized {
                    AuthBanner()
                        .padding(.horizontal, Theme.Spacing.l)
                } else if let error = model.error {
                    ErrorBanner(message: error, cachedAt: model.cachedAt)
                        .padding(.horizontal, Theme.Spacing.l)
                }

                if let detail = model.detail {
                    if detail.positions.count <= 1 {
                        ErrorBanner(message: "这段行程没有位置数据")
                            .padding(.horizontal, Theme.Spacing.l)
                    }

                    map(detail.positions, drive: detail.drive)
                    summary(detail)
                    charts(detail)
                    facts(detail.drive)
                } else if model.isLoading {
                    VStack(spacing: Theme.Spacing.l) {
                        Skeleton(height: 260, cornerRadius: Theme.Radius.tile)
                        Skeleton(height: 96)
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
            await model.load(client: settings.client, carId: settings.carId, driveId: driveId)
        }
    }

    // MARK: Map

    @ViewBuilder
    private func map(_ positions: [Position], drive: Drive) -> some View {
        if positions.count > 1 {
            MapSurface(
                content: .track(points: positions.map {
                    $0.mapCoordinate(correction: settings.mapOffsetCorrection)
                }),
                height: 260,
                label: "行程轨迹，\(Fmt.km(drive.distanceKm))，从 \(drive.startTitle) 到 \(drive.endTitle)"
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .strokeBorder(Theme.glassRim, lineWidth: 1)
            }
            .overlay(alignment: .bottomLeading) {
                MapOverlayPill(
                    text: "\(drive.startTitle) → \(drive.endTitle)",
                    systemImage: "mappin.and.ellipse"
                )
                .padding(Theme.Spacing.s)
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
    }

    // MARK: Summary

    private func summary(_ detail: DriveDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(Fmt.dateTime(detail.drive.startDate))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xl) {
                stat(Fmt.km(detail.drive.distanceKm), "里程")
                stat(Fmt.duration(minutes: detail.drive.durationMin), "时长")
                stat(Fmt.kwh(detail.energyKwh), "能耗")
            }

            if let consumption = consumption(detail) {
                let badge = String(format: "%.1f kWh/100km", consumption)
                // FR-4.6 — colour is not readable by VoiceOver, so the level is in the value.
                Text(badge)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(consumption < 18 ? Theme.green : Theme.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        (consumption < 18 ? Theme.green : Theme.orange).opacity(0.14),
                        in: Capsule()
                    )
                    .accessibilityLabel("平均能耗")
                    .accessibilityValue("\(badge)，\(consumption < 18 ? "正常" : "偏高")")
            }
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

    private func consumption(_ detail: DriveDetailResponse) -> Double? {
        guard let energy = detail.energyKwh,
              let distance = detail.drive.distanceKm,
              distance >= 0.5
        else { return nil }
        return energy / distance * 100
    }

    // MARK: Charts

    private func charts(_ detail: DriveDetailResponse) -> some View {
        let positions = detail.positions
        let domain = xDomain(positions)

        return VStack(spacing: Theme.Spacing.l) {
            if let domain {
                let speeds = points(positions, \.speed)
                if speeds.count > 1 {
                    MetricChart(
                        title: "速度",
                        unit: "km/h",
                        color: Theme.accent,
                        points: speeds,
                        summary: speedSummary(speeds),
                        xDomain: domain
                    )
                }

                let powers = points(positions, \.power)
                if powers.count > 1 {
                    MetricChart(
                        title: "功率",
                        unit: "kW",
                        color: Theme.purple,
                        points: powers,
                        summary: powerSummary(powers),
                        xDomain: domain
                    )
                }

                let batteries = points(positions, \.batteryLevel)
                if batteries.count > 1 {
                    MetricChart(
                        title: "电量",
                        unit: "%",
                        color: Theme.green,
                        points: batteries,
                        summary: batterySummary(batteries),
                        xDomain: domain
                    )
                }

                let elevations = points(positions, \.elevation)
                if elevations.count > 1, elevations.count * 10 >= positions.count * 3 {
                    MetricChart(
                        title: "海拔",
                        unit: "m",
                        color: Theme.teal,
                        points: elevations,
                        summary: elevationSummary(elevations),
                        xDomain: domain
                    )
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func xDomain(_ positions: [Position]) -> ClosedRange<Date>? {
        guard let first = positions.first?.date,
              let last = positions.last?.date,
              first < last
        else { return nil }
        return first...last
    }

    private func points(_ positions: [Position], _ keyPath: KeyPath<Position, Int?>) -> [MetricPoint] {
        positions.compactMap { position in
            position[keyPath: keyPath].map { MetricPoint(date: position.date, value: Double($0)) }
        }
    }

    private func speedSummary(_ points: [MetricPoint]) -> String {
        guard let max = points.map(\.value).max() else { return "—" }
        return String(format: "最高 %.0f km/h", max)
    }

    private func powerSummary(_ points: [MetricPoint]) -> String {
        guard let min = points.map(\.value).min() else { return "—" }
        return String(format: "最低 %.0f kW", min)
    }

    private func batterySummary(_ points: [MetricPoint]) -> String {
        guard let last = points.last?.value else { return "—" }
        return String(format: "%.0f%%", last)
    }

    private func elevationSummary(_ points: [MetricPoint]) -> String {
        guard let max = points.map(\.value).max() else { return "—" }
        return String(format: "最高 %.0f m", max)
    }

    // MARK: Facts

    private func facts(_ drive: Drive) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            factRow("起点", drive.startTitle)
            factRow("终点", drive.endTitle)
            factRow("车外均温", Fmt.temp(drive.outsideTempAvg))
            factRow("车内均温", Fmt.temp(drive.insideTempAvg))
            factRow("爬升 / 下降", climb(drive))
            factRow("续航消耗", Fmt.km(drive.rangeUsedKm))
        }
        .card()
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func factRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.l) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func climb(_ drive: Drive) -> String {
        let ascent = drive.ascent.map { "\($0) m" } ?? "—"
        let descent = drive.descent.map { "\($0) m" } ?? "—"
        return "\(ascent) / \(descent)"
    }
}
