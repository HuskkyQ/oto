import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var model = StatsViewModel()
    @State private var showHistory = false
    @State private var showEnergy = false
    @State private var showRegen = false
    @State private var showBattery = false

    private var taskKey: String {
        "\(settings.carId)-\(model.period.rawValue)-\(model.bucket.rawValue)"
    }

    var body: some View {
        NavigationStack {
            ScreenScaffold(
                title: "统计",
                actions: [
                    HeaderAction("arrow.clockwise", label: "刷新") {
                        Task { await model.load(client: settings.client, carId: settings.carId) }
                    }
                ]
            ) {
                VStack(spacing: Theme.Spacing.l) {
                    filters
                    content
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showHistory) {
                HistoryView(initialPeriod: model.period)
            }
            .navigationDestination(isPresented: $showEnergy) {
                EnergyView()
            }
            .navigationDestination(isPresented: $showRegen) {
                RegenView()
            }
            .navigationDestination(isPresented: $showBattery) {
                BatteryView()
            }
        }
        .task(id: taskKey) {
            await model.load(client: settings.client, carId: settings.carId)
        }
    }

    private var filters: some View {
        HStack(spacing: Theme.Spacing.s) {
            SegmentedControl(
                options: StatsViewModel.Period.allCases.map {
                    SegmentOption(value: $0, label: $0.label)
                },
                selection: $model.period,
                compact: true
            )

            // Two bare-text groups side by side need a mark between them.
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1, height: 16)
                .accessibilityHidden(true)

            SegmentedControl(
                options: StatsViewModel.Bucket.allCases.map {
                    SegmentOption(value: $0, label: $0.label)
                },
                selection: $model.bucket,
                compact: true
            )
            .frame(width: 104)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.buckets.isEmpty {
            VStack(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    Skeleton(height: 88, cornerRadius: Theme.Radius.tile)
                    Skeleton(height: 88, cornerRadius: Theme.Radius.tile)
                }
                HStack(spacing: Theme.Spacing.s) {
                    Skeleton(height: 88, cornerRadius: Theme.Radius.tile)
                    Skeleton(height: 88, cornerRadius: Theme.Radius.tile)
                }
                Skeleton(height: 190)
                Skeleton(height: 190)
            }
            .padding(.horizontal, Theme.Spacing.l)
        } else if model.buckets.isEmpty, model.unauthorized {
            EmptyStateView(
                systemImage: "key.slash",
                title: "无法读取统计",
                message: "Token 无效或已失效。",
                actionTitle: "去设置",
                action: { settings.wantsSettings = true }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else if let error = model.error, model.buckets.isEmpty {
            EmptyStateView(
                systemImage: "wifi.exclamationmark",
                title: "无法读取统计",
                message: error,
                actionTitle: "重试",
                action: { Task { await model.load(client: settings.client, carId: settings.carId) } }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else if !model.hasRecords {
            EmptyStateView(
                systemImage: "chart.bar.fill",
                title: "这段时间没有记录",
                message: "换一个时间段看看。",
                actionTitle: "切换时间段",
                action: { model.period = model.period == .week ? .month : .week }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else {
            if model.unauthorized {
                AuthBanner()
                    .padding(.horizontal, Theme.Spacing.l)
            } else if let error = model.error {
                ErrorBanner(
                    message: error,
                    cachedAt: model.cachedAt,
                    retry: { Task { await model.load(client: settings.client, carId: settings.carId) } }
                )
                .padding(.horizontal, Theme.Spacing.l)
            }

            entries
            tiles
            charts
        }
    }

    /// C-13 — the discovery entries below the charts. Stats itself never instantiates a map.
    private var entries: some View {
        VStack(spacing: Theme.Spacing.s) {
            entryCard(
                icon: "map",
                tint: Theme.accent,
                title: "历史轨迹地图",
                subtitle: "回放近 \(model.period.rawValue) 天的行驶路线"
            ) { showHistory = true }

            entryCard(
                icon: "chart.line.uptrend.xyaxis",
                tint: Theme.purple,
                title: "能耗分析",
                subtitle: "按软件版本、季节、温度比较百公里能耗"
            ) { showEnergy = true }

            entryCard(
                icon: "arrow.down.circle",
                tint: Theme.green,
                title: "动能回收",
                subtitle: "近七天的回收电量与峰值功率"
            ) { showRegen = true }

            entryCard(
                icon: "battery.75percent",
                tint: Theme.teal,
                title: "电池报告",
                subtitle: "由充电数据推算容量与续航保持率"
            ) { showBattery = true }
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func entryCard(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(
                        tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.Spacing.m)
            .card()
        }
        .buttonStyle(.plain)
    }

    private var tiles: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Theme.Spacing.s),
                GridItem(.flexible(), spacing: Theme.Spacing.s)
            ],
            spacing: Theme.Spacing.s
        ) {
            StatTile(
                icon: "road.lanes",
                title: "总里程",
                value: Fmt.km(model.totalDistanceKm),
                tint: Theme.accent
            )
            StatTile(
                icon: "car.fill",
                title: "行程次数",
                value: "\(model.totalDriveCount)",
                tint: Theme.green
            )
            StatTile(
                icon: "bolt.fill",
                title: "充电电量",
                value: Fmt.kwh(model.totalEnergyKwh),
                tint: Theme.teal
            )
            StatTile(
                icon: "yensign.circle",
                title: "充电费用",
                value: model.totalCost.map { "¥\(Fmt.money($0))" } ?? "—",
                tint: Theme.orange
            )
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    private var charts: some View {
        VStack(spacing: Theme.Spacing.l) {
            BarChart(
                title: model.bucket == .day ? "每日里程" : "每月里程",
                unit: "km",
                color: Theme.accent,
                points: model.distancePoints(),
                summary: Fmt.km(model.totalDistanceKm),
                unitWidth: model.bucket.component
            )

            BarChart(
                title: model.bucket == .day ? "每日充电电量" : "每月充电电量",
                unit: "kWh",
                color: Theme.teal,
                points: model.energyPoints(),
                summary: Fmt.kwh(model.totalEnergyKwh),
                unitWidth: model.bucket.component
            )

            BarChart(
                title: model.bucket == .day ? "每日行程时长" : "每月行程时长",
                unit: "min",
                color: Theme.purple,
                points: model.durationPoints(),
                summary: Fmt.duration(minutes: model.totalDurationMin),
                unitWidth: model.bucket.component
            )
        }
        .padding(.horizontal, Theme.Spacing.l)
    }
}
