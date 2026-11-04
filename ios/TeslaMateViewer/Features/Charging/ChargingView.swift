import SwiftUI

struct ChargingView: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var model = ChargingViewModel()

    private var taskKey: String {
        "\(settings.carId)-\(model.period.rawValue)"
    }

    var body: some View {
        NavigationStack {
            ScreenScaffold(title: "充电", scrollResetToken: model.period.rawValue) {
                VStack(spacing: Theme.Spacing.l) {
                    SegmentedControl(
                        options: ChargingViewModel.Period.allCases.map {
                            SegmentOption(value: $0, label: $0.label)
                        },
                        selection: $model.period
                    )
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.top, Theme.Spacing.s)

                    content
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Int.self) { chargeId in
                ChargeDetailView(chargeId: chargeId)
            }
        }
        .task(id: taskKey) {
            await model.load(client: settings.client, carId: settings.carId)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.charges.isEmpty {
            VStack(spacing: Theme.Spacing.s) {
                ForEach(0..<4, id: \.self) { _ in Skeleton(height: 104) }
            }
            .padding(.horizontal, Theme.Spacing.l)
        } else if model.charges.isEmpty, model.unauthorized {
            EmptyStateView(
                systemImage: "key.slash",
                title: "无法读取充电记录",
                message: "Token 无效或已失效。",
                actionTitle: "去设置",
                action: { settings.wantsSettings = true }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else if let error = model.error, model.charges.isEmpty {
            EmptyStateView(
                systemImage: "wifi.exclamationmark",
                title: "无法读取充电记录",
                message: error,
                actionTitle: "重试",
                action: { Task { await model.load(client: settings.client, carId: settings.carId) } }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else if model.charges.isEmpty {
            EmptyStateView(
                systemImage: "bolt.fill",
                title: "这段时间没有充电记录",
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

            summary
            list
            footer
        }
    }

    private var summary: some View {
        StatStrip(columns: [
            (Fmt.kwh(model.totalEnergyKwh), "已充"),
            ("\(model.charges.count) 次", "充电"),
            (model.totalCost.map { "¥\(Fmt.money($0))" } ?? "费用未记录", "费用")
        ])
        .padding(.horizontal, Theme.Spacing.l)
    }

    private var list: some View {
        LazyVStack(spacing: Theme.Spacing.s) {
            ForEach(model.charges) { charge in
                NavigationLink(value: charge.id) {
                    ChargeRow(charge: charge)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Spacing.l)
                .onAppear { loadMoreIfNeeded(charge) }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoadingMore {
            ListFooter(state: .loading)
        } else if let error = model.error, model.cachedAt == nil {
            ListFooter(state: .failed(error), retry: {
                Task { await model.loadMore(client: settings.client, carId: settings.carId) }
            })
        } else if !model.hasMore {
            ListFooter(state: .end, endText: "没有更多充电记录")
        }
    }

    private func loadMoreIfNeeded(_ charge: ChargingSession) {
        guard let index = model.charges.firstIndex(where: { $0.id == charge.id }) else { return }
        guard index >= model.charges.count - 20 else { return }

        Task { await model.loadMore(client: settings.client, carId: settings.carId) }
    }
}
