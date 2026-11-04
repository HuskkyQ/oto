import SwiftUI

/// 05 — parking sessions derived from the gaps between drives and charges.
struct ParkingView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var chrome: TabBarChrome
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ParkingViewModel()

    var body: some View {
        ScreenScaffold(
            title: "停车记录",
            backAction: { dismiss() },
            actions: [
                HeaderAction("arrow.clockwise", label: "刷新") {
                    Task { await load() }
                }
            ]
        ) {
            VStack(spacing: Theme.Spacing.l) {
                SegmentedControl(
                    options: ParkingViewModel.Period.allCases.map {
                        SegmentOption(value: $0, label: $0.label)
                    },
                    selection: $model.period,
                    compact: true
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
        .task(id: "\(settings.carId)-\(model.period.rawValue)") {
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
                Skeleton(height: 420)
            }
            .padding(.horizontal, Theme.Spacing.l)
        } else if model.unauthorized, model.response == nil {
            EmptyStateView(
                systemImage: "key.slash",
                title: "无法读取停车记录",
                message: "Token 无效或已失效。",
                actionTitle: "去设置",
                action: { settings.wantsSettings = true }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else if let error = model.error, model.response == nil {
            EmptyStateView(
                systemImage: "wifi.exclamationmark",
                title: "无法读取停车记录",
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

            if response.sessions.isEmpty {
                EmptyStateView(
                    systemImage: "parkingsign",
                    title: "没有停车记录",
                    message: "这段时间行程与充电之间没有超过 10 分钟的空档。",
                    actionTitle: "换一个时间段",
                    action: { model.period = model.period == .week ? .month : .week }
                )
                .padding(.horizontal, Theme.Spacing.l)
            } else {
                summary(response)
                list(response)
            }

            Text("停车区间由相邻行程与充电的空档推导，最短 10 分钟；跨午夜的停车不拆分，按一次计。")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.l)
        }
    }

    private func summary(_ response: ParkingResponse) -> some View {
        StatStrip(columns: [
            ("\(response.sessions.count)", "停车"),
            (Fmt.durationCompact(minutes: response.totalMinutes), "总时长"),
            (response.averagePowerW.map { "\($0) W" } ?? "—", "平均功率"),
            (response.totalEnergyKwh.map { String(format: "%.2f kWh", $0) } ?? "—", "耗电")
        ])
        .card()
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func list(_ response: ParkingResponse) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(response.sessions.enumerated()), id: \.element.id) { index, session in
                NavigationLink {
                    ParkingDetailView(session: session)
                } label: {
                    ParkingRow(session: session)
                }
                .buttonStyle(.plain)

                if index < response.sessions.count - 1 {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.leading, Theme.Spacing.l)
                }
            }
        }
        .card()
        .padding(.horizontal, Theme.Spacing.l)
    }
}

/// One row of the list: place, window, battery, energy and the asleep/online split.
struct ParkingRow: View {
    let session: ParkingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: Theme.Spacing.s)

                Text(Fmt.durationCompact(minutes: session.durationMin))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(meta)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 4)

                Text(session.energyKwh.map { String(format: "%.2f kWh", $0) } ?? "—")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }

            ProportionBar(slices: ParkingLegend.slices(session.stateMinutes), showsLegend: false)

            ParkingStateLegend(session: session)
        }
        .padding(.vertical, Theme.Spacing.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        var parts = [Fmt.rangeLabel(from: session.startDate, to: session.endDate)]
        if let level = session.endBatteryLevel ?? session.startBatteryLevel { parts.append("\(level)%") }
        if let range = session.endRangeKm ?? session.startRangeKm {
            parts.append(String(format: "%.0f km", range))
        }
        return parts.joined(separator: " · ")
    }
}

/// The legend under a parking bar: each state's share, then the average power.
struct ParkingStateLegend: View {
    let session: ParkingSession

    var body: some View {
        let total = max(session.stateMinutes.reduce(0) { $0 + $1.minutes }, 1)

        HStack(spacing: Theme.Spacing.m) {
            ForEach(session.stateMinutes.prefix(3)) { entry in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(statusColor(entry.state))
                        .frame(width: 6, height: 6)

                    Text(statusLabel(entry.state))
                        .foregroundStyle(Theme.textSecondary)

                    Text("\(Int((Double(entry.minutes) / Double(total) * 100).rounded()))%")
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)

            Text(session.averagePowerW.map { "均 \($0) W" } ?? "均 —")
                .foregroundStyle(Theme.textFaint)
                .monospacedDigit()
        }
        .font(.system(size: 10.5))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}

enum ParkingLegend {
    static func slices(_ entries: [ParkingStateMinutes]) -> [ProportionSlice] {
        entries.map {
            ProportionSlice(label: statusLabel($0.state), value: Double($0.minutes), color: statusColor($0.state))
        }
    }
}
