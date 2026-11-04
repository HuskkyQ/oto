import SwiftUI

/// 09 — today's recovered energy, this week's peak power and the versions it was measured on.
struct RegenView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var chrome: TabBarChrome
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = RegenViewModel()

    var body: some View {
        ScreenScaffold(
            title: "动能回收",
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
        if model.isLoading, model.response == nil {
            VStack(spacing: Theme.Spacing.l) {
                Skeleton(height: 108, cornerRadius: Theme.Radius.tile)
                Skeleton(height: 160)
                Skeleton(height: 140)
            }
            .padding(.horizontal, Theme.Spacing.l)
        } else if model.unauthorized, model.response == nil {
            EmptyStateView(
                systemImage: "key.slash",
                title: "无法读取回收数据",
                message: "Token 无效或已失效。",
                actionTitle: "去设置",
                action: { settings.wantsSettings = true }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else if let error = model.error, model.response == nil {
            EmptyStateView(
                systemImage: "wifi.exclamationmark",
                title: "无法读取回收数据",
                message: error,
                actionTitle: "重试",
                action: { Task { await load() } }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else if let response = model.response {
            if model.unauthorized {
                AuthBanner().padding(.horizontal, Theme.Spacing.l)
            } else if let error = model.error {
                ErrorBanner(message: error, cachedAt: model.cachedAt, retry: { Task { await load() } })
                    .padding(.horizontal, Theme.Spacing.l)
            }

            if response.days.isEmpty {
                EmptyStateView(
                    systemImage: "arrow.down.circle",
                    title: "近七天没有行程",
                    message: "没有行程就没有可回收的能量。",
                    actionTitle: "重试",
                    action: { Task { await load() } }
                )
                .padding(.horizontal, Theme.Spacing.l)
            } else {
                today(response)
                week(response)
                versions(response)
                notes
            }
        }
    }

    private func today(_ response: RegenResponse) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("今日")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            StatStrip(columns: [
                (response.today.map { String(format: "%.1f kWh", $0.regenKwh) } ?? "—", "回收电量"),
                (response.today.flatMap(todayShare).map { "\(Int(($0 * 100).rounded()))%" } ?? "—", "回收效率"),
                (response.today.map { Fmt.durationCompact(minutes: $0.minutes) } ?? "—", "回收时长")
            ])

            Text("回收效率 = 回收电量 ÷（回收电量 + 行驶耗电）。")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, Theme.Spacing.l)
    }

    /// `/regen` reports a share for the whole range; today's share is recovered ÷ its own total.
    private func todayShare(_ day: RegenDay) -> Double? {
        let total = day.regenKwh + day.consumedKwh
        guard total > 0 else { return nil }
        return day.regenKwh / total
    }

    private func week(_ response: RegenResponse) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("本周回收功率")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Text(String(format: "最高 %.0f kW", response.weekPeakKw))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
            }

            MiniBars(
                bars: model.weekBars,
                summary: String(format: "本周峰值 %.0f kW", response.weekPeakKw),
                trailing: String(format: "共回收 %.1f kWh", response.totalRegenKwh)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, Theme.Spacing.l)
    }

    @ViewBuilder
    private func versions(_ response: RegenResponse) -> some View {
        if !response.versions.isEmpty {
            SettingsGroup {
                ForEach(Array(response.versions.prefix(3).enumerated()), id: \.element.id) { index, version in
                    SettingsRow(
                        title: version.label,
                        value: String(format: "峰值 %.0f kW · %.1f kWh", version.peakKw, version.regenKwh),
                        showsDivider: index < min(response.versions.count, 3) - 1
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
    }

    private var notes: some View {
        Text("回收功率取负功率的绝对值；充电时流入电池的功率同样为负，因此只统计行程中的采样。")
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.textFaint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Spacing.l)
    }
}
