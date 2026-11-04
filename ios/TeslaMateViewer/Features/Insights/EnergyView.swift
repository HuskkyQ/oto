import SwiftUI

/// 08 — consumption per software version, season or temperature.
struct EnergyView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var chrome: TabBarChrome
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = EnergyViewModel()

    var body: some View {
        ScreenScaffold(
            title: "能耗分析",
            backAction: { dismiss() },
            actions: [
                HeaderAction("arrow.clockwise", label: "刷新") {
                    Task { await load() }
                }
            ]
        ) {
            VStack(spacing: Theme.Spacing.l) {
                SegmentedControl(
                    options: EnergyViewModel.Grouping.allCases.map {
                        SegmentOption(value: $0, label: $0.label)
                    },
                    selection: $model.grouping
                )
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.s)

                content
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        .toolbar(.hidden, for: .navigationBar)
        .interactiveBackEnabled()
        .contentMargins(.bottom, 0, for: .scrollContent)
        .onAppear { chrome.hide() }
        .onDisappear { chrome.show() }
        .task(id: "\(settings.carId)-\(model.grouping.rawValue)") {
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
                Skeleton(height: 88, cornerRadius: Theme.Radius.tile)
                Skeleton(height: 320)
                Skeleton(height: 180)
            }
            .padding(.horizontal, Theme.Spacing.l)
        } else if model.unauthorized, model.response == nil {
            EmptyStateView(
                systemImage: "key.slash",
                title: "无法读取能耗",
                message: "Token 无效或已失效。",
                actionTitle: "去设置",
                action: { settings.wantsSettings = true }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else if let error = model.error, model.response == nil {
            EmptyStateView(
                systemImage: "wifi.exclamationmark",
                title: "无法读取能耗",
                message: error,
                actionTitle: "重试",
                action: { Task { await load() } }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else if let response = model.response, response.groups.isEmpty {
            EmptyStateView(
                systemImage: "bolt.slash",
                title: "没有可比较的行程",
                message: "这段时间没有带功率采样的行程，换一个分组或稍后再看。",
                actionTitle: "换一个分组",
                action: { model.grouping = model.grouping == .version ? .season : .version }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else if let response = model.response {
            if model.unauthorized {
                AuthBanner().padding(.horizontal, Theme.Spacing.l)
            } else if let error = model.error {
                ErrorBanner(message: error, cachedAt: model.cachedAt, retry: { Task { await load() } })
                    .padding(.horizontal, Theme.Spacing.l)
            }

            summary(response)
            breakdown(response)
            distances(response)
            notes(response)
        }
    }

    private func summary(_ response: EnergyResponse) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            StatStrip(columns: [
                (response.averageWhPerKm.map { "\($0)" } ?? "—", "平均 Wh/km"),
                (response.best?.label ?? "—", model.grouping.bestLabel),
                (response.best.map { String(format: "%.1f%%", $0.spreadPercent) } ?? "—", "差异")
            ])

            Text("累计 \(Fmt.km(response.totalKm, decimals: 0)) · \(response.groups.count) 个\(unitNouns)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card()
        .padding(.horizontal, Theme.Spacing.l)
    }

    private var unitNouns: String {
        switch model.grouping {
        case .version: return "版本"
        case .season: return "季节"
        case .temperature: return "温度区间"
        }
    }

    private func breakdown(_ response: EnergyResponse) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text("各\(unitNouns)平均能耗")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Text("越低越好")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
            }

            ForEach(response.groups) { group in
                row(group, in: response)
            }

            if let mean = model.meanWhPerKm, model.meanFraction() != nil {
                Text("竖线为全部\(unitNouns)均值 \(mean) Wh/km；差值相对均值计算。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func row(_ group: EnergyGroup, in response: EnergyResponse) -> some View {
        let isBest = response.best?.key == group.key
        let isLatest = model.grouping == .version && response.latestKey == group.key
        let delta = model.delta(group)
        let fraction = model.barFraction(group)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(group.label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                if isLatest {
                    Text("最新")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(.white.opacity(0.10), in: Capsule())
                }

                Spacer(minLength: 4)

                Text("\(group.whPerKm)")
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)

                if let delta, abs(delta) >= 0.05 {
                    // Colour alone does not reach VoiceOver, so the sign is in the text.
                    Text(String(format: "%@%.1f%%", delta < 0 ? "−" : "+", abs(delta)))
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(delta < 0 ? Theme.green : Theme.orange)
                } else if delta != nil {
                    Text("持平")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.textFaint)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.06))

                    Capsule()
                        .fill(isBest ? Theme.green.opacity(0.75) : Theme.accent.opacity(0.55))
                        .frame(width: max(4, proxy.size.width * fraction))

                    if let mean = model.meanFraction() {
                        Rectangle()
                            .fill(.white.opacity(0.35))
                            .frame(width: 1.2)
                            .offset(x: max(0, proxy.size.width * mean - 0.6))
                    }
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.label) \(group.whPerKm) Wh/km，\(group.driveCount) 次行程，\(Fmt.km(group.km, decimals: 0))")
    }

    private func distances(_ response: EnergyResponse) -> some View {
        SettingsGroup {
            ForEach(Array(response.groups.enumerated()), id: \.element.id) { index, group in
                SettingsRow(
                    title: group.label,
                    value: "\(Fmt.km(group.km, decimals: 0)) · \(period(group))",
                    showsDivider: index < response.groups.count - 1
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func period(_ group: EnergyGroup) -> String {
        let calendar = Calendar.current
        let start = Fmt.monthDay(group.fromDate)
        let end = calendar.isDateInToday(group.toDate) ? "至今" : Fmt.monthDay(group.toDate)
        return "\(start) – \(end)"
    }

    @ViewBuilder
    private func notes(_ response: EnergyResponse) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if !model.hasVersionData {
                Text("TeslaMate 没有记录软件更新，全部行程归入同一组；切到季节或温度才有比较。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.orange)
            }

            Text("能耗口径：行程耗电 ÷ 里程，按里程加权；耗电由位置点功率积分得出，相邻采样超过 300 秒不计入，不足 1 km 的行程不计入。")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textFaint)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.Spacing.l)
    }
}
