import SwiftUI

/// 07 — battery health inferred from the car's own charging sessions.
struct BatteryView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var chrome: TabBarChrome
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = BatteryViewModel()

    var body: some View {
        ScreenScaffold(
            title: "电池报告",
            backAction: { dismiss() },
            actions: [
                HeaderAction("arrow.clockwise", label: "刷新") {
                    Task { await load() }
                }
            ]
        ) {
            VStack(spacing: Theme.Spacing.l) {
                content
            }
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .toolbar(.hidden, for: .navigationBar)
        .interactiveBackEnabled()
        .contentMargins(.bottom, 0, for: .scrollContent)
        .onAppear { chrome.hide() }
        .onDisappear { chrome.show() }
        .task(id: settings.carId) {
            await load()
        }
    }

    private func load() async {
        await model.load(client: settings.client, carId: settings.carId)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading, model.report == nil {
            VStack(spacing: Theme.Spacing.l) {
                Skeleton(height: 160, cornerRadius: Theme.Radius.tile)
                Skeleton(height: 88, cornerRadius: Theme.Radius.tile)
                Skeleton(height: 160)
            }
            .padding(.horizontal, Theme.Spacing.l)
        } else if model.unauthorized, model.report == nil {
            EmptyStateView(
                systemImage: "key.slash",
                title: "无法读取电池报告",
                message: "Token 无效或已失效。",
                actionTitle: "去设置",
                action: { settings.wantsSettings = true }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else if let error = model.error, model.report == nil {
            EmptyStateView(
                systemImage: "wifi.exclamationmark",
                title: "无法读取电池报告",
                message: error,
                actionTitle: "重试",
                action: { Task { await load() } }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else if let report = model.report, !model.hasSamples {
            EmptyStateView(
                systemImage: "battery.0percent",
                title: "还没有可用的充电样本",
                message: "需要一次跨度不少于 40 个百分点的充电才能估算容量，例如 30% 充到 75%。",
                actionTitle: "重试",
                action: { Task { await load() } }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else if let report = model.report {
            if model.unauthorized {
                AuthBanner().padding(.horizontal, Theme.Spacing.l)
            } else if let error = model.error {
                ErrorBanner(message: error, cachedAt: model.cachedAt, retry: { Task { await load() } })
                    .padding(.horizontal, Theme.Spacing.l)
            }

            score(report)
            tiles(report)
            analysis(report)
            samples(report)
            notes
        }
    }

    @ViewBuilder
    private func score(_ report: BatteryReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let score = report.score, let rating = report.rating {
                ScoreRing(
                    score: score,
                    caption: "健康度",
                    verdict: rating,
                    detail: subtitle(report),
                    tint: tint(for: rating)
                )
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("样本积累中")
                        .font(.headline)
                        .foregroundStyle(Theme.textSecondary)
                    Text(subtitle(report))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Text("分数为估算值，随样本增加而变化；样本不足 3 次时不显示评级。")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func subtitle(_ report: BatteryReport) -> String {
        var parts: [String] = []
        if let odometer = report.odometerKm {
            parts.append("累计 \(Int(odometer.rounded()).formatted()) km")
        }
        parts.append("\(report.sampleCount) 次充电样本")
        return parts.joined(separator: " · ")
    }

    private func tint(for rating: String) -> Color {
        switch rating {
        case "优秀": return Theme.green
        case "良好": return Theme.accent
        case "偏低": return Theme.orange
        default: return Theme.red
        }
    }

    private func tiles(_ report: BatteryReport) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Theme.Spacing.s),
                GridItem(.flexible(), spacing: Theme.Spacing.s)
            ],
            spacing: Theme.Spacing.s
        ) {
            StatTile(
                icon: "arrow.down.right",
                title: "容量衰减",
                value: percent(report.capacityLossPercent),
                tint: Theme.orange
            )
            StatTile(
                icon: "arrow.down.right",
                title: "续航衰减",
                value: percent(report.rangeLossPercent),
                tint: Theme.orange
            )
            StatTile(
                icon: "battery.75percent",
                title: "容量保持率",
                value: percent(report.capacityRetention.map { $0 * 100 }),
                tint: Theme.green
            )
            StatTile(
                icon: "road.lanes",
                title: "续航保持率",
                value: percent(report.rangeRetention.map { $0 * 100 }),
                tint: Theme.green
            )
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    private func analysis(_ report: BatteryReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text("衰减分析")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Text("容量 / 续航")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
            }

            bar(
                "容量",
                current: report.capacityKwh.map { String(format: "%.1f", $0) },
                baseline: report.baselineCapacityKwh.map { String(format: "%.1f", $0) },
                unit: " kWh",
                retention: report.capacityRetention
            )

            bar(
                "续航",
                current: report.fullRangeKm.map { "\($0)" },
                baseline: report.baselineRangeKm.map { "\($0)" },
                unit: " km",
                retention: report.rangeRetention
            )

            Text("灰色轨道末端为观测到的最好水平，右侧空出的部分就是衰减量；容量由充电数据推算，不是车辆上报值。")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func bar(
        _ title: String,
        current: String?,
        baseline: String?,
        unit: String,
        retention: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                Text("\(current ?? "—") / \(baseline ?? "—")\(unit)")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.06))
                    Capsule()
                        .fill(retention == nil ? Theme.textFaint : Theme.green.opacity(0.65))
                        .frame(width: max(4, proxy.size.width * CGFloat(min(max(retention ?? 0, 0), 1))))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，当前 \(current ?? "未知")，最好 \(baseline ?? "未知")\(unit)")
    }

    private func samples(_ report: BatteryReport) -> some View {
        SettingsGroup {
            SettingsRow(title: "充电样本", value: "\(report.sampleCount) 次", showsDivider: true)
            SettingsRow(title: "最近一次样本", value: Fmt.dateTime(report.lastChargeDate), showsDivider: false)
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    private var notes: some View {
        Text("样本要求：一次充电跨度不少于 40 个百分点、充入电量大于 5 kWh。容量 = 充入电量 ÷ 电量变化；最近 10 次的中位数与历史最好水平相比得出保持率。")
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.textFaint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Spacing.l)
    }
}
