import SwiftUI

struct DrivesView: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var model = DrivesViewModel()
    @State private var showHistory = false
    @State private var showCalendar = false
    @State private var showParking = false

    private var taskKey: String {
        "\(settings.carId)-\(model.period.rawValue)"
    }

    var body: some View {
        NavigationStack {
            ScreenScaffold(
                title: "行程",
                actions: [
                    HeaderAction("calendar", label: "行程日历") { showCalendar = true },
                    HeaderAction("parkingsign", label: "停车记录") { showParking = true },
                    HeaderAction("map", label: "轨迹") { showHistory = true }
                ],
                scrollResetToken: model.period.rawValue
            ) {
                VStack(spacing: Theme.Spacing.l) {
                    SegmentedControl(
                        options: DrivesViewModel.Period.allCases.map {
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
            .navigationDestination(for: Int.self) { driveId in
                DriveDetailView(driveId: driveId)
            }
            .navigationDestination(isPresented: $showHistory) {
                HistoryView(initialPeriod: model.period)
            }
            .navigationDestination(isPresented: $showCalendar) {
                TripCalendarView()
            }
            .navigationDestination(isPresented: $showParking) {
                ParkingView()
            }
        }
        .task(id: taskKey) {
            await model.load(client: settings.client, carId: settings.carId)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.drives.isEmpty {
            VStack(spacing: Theme.Spacing.s) {
                ForEach(0..<5, id: \.self) { _ in Skeleton(height: 96) }
            }
            .padding(.horizontal, Theme.Spacing.l)
        } else if model.drives.isEmpty, model.unauthorized {
            EmptyStateView(
                systemImage: "key.slash",
                title: "无法读取行程",
                message: "Token 无效或已失效。",
                actionTitle: "去设置",
                action: { settings.wantsSettings = true }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else if let error = model.error, model.drives.isEmpty {
            EmptyStateView(
                systemImage: "wifi.exclamationmark",
                title: "无法读取行程",
                message: error,
                actionTitle: "重试",
                action: { Task { await model.load(client: settings.client, carId: settings.carId) } }
            )
            .padding(.horizontal, Theme.Spacing.l)
        } else if model.drives.isEmpty {
            EmptyStateView(
                systemImage: "car.fill",
                title: "这段时间没有行程",
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
            (Fmt.km(model.totalDistanceKm), "总里程"),
            ("\(model.drives.count) 次", "行程"),
            (Fmt.duration(minutes: model.totalDurationMin), "总时长"),
            (model.averageSpeedKmh.map { "\(Int($0.rounded())) km/h" } ?? "—", "均速")
        ])
        .padding(.horizontal, Theme.Spacing.l)
    }

    private var list: some View {
        LazyVStack(spacing: Theme.Spacing.s) {
            ForEach(model.days) { day in
                Section {
                    ForEach(day.drives) { drive in
                        NavigationLink(value: drive.id) {
                            TripRow(drive: drive)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Theme.Spacing.l)
                        .onAppear { loadMoreIfNeeded(drive) }
                    }
                } header: {
                    StickyDayHeader(date: day.id, distanceKm: day.distanceKm)
                }
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
            ListFooter(state: .end)
        }
    }

    private func loadMoreIfNeeded(_ drive: Drive) {
        guard let index = model.drives.firstIndex(where: { $0.id == drive.id }) else { return }
        guard index >= model.drives.count - 20 else { return }

        Task { await model.loadMore(client: settings.client, carId: settings.carId) }
    }
}
