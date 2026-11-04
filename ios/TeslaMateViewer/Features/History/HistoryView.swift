import MapKit
import SwiftUI

/// FR-7 — map-first track for a range. Pushed from Drives and Stats, never a tab.
struct HistoryView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var chrome: TabBarChrome
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: HistoryViewModel
    @State private var showFilter = false

    init(initialPeriod: DrivesViewModel.Period = .month) {
        _model = StateObject(wrappedValue: HistoryViewModel(period: initialPeriod))
    }

    private var taskKey: String {
        let custom = model.customRange.map { "\($0.lowerBound.timeIntervalSince1970)-\($0.upperBound.timeIntervalSince1970)" } ?? "none"
        return "\(settings.carId)-\(model.period.rawValue)-\(custom)"
    }

    var body: some View {
        ZStack {
            ScreenBackground()

            VStack(spacing: 0) {
                HeaderBar(
                    title: "历史轨迹",
                    backAction: { dismiss() },
                    actions: [HeaderAction("slider.horizontal.3", label: "筛选") { showFilter = true }]
                )

                filters

                if model.unauthorized {
                    AuthBanner()
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.top, Theme.Spacing.s)
                } else if let error = model.error {
                    ErrorBanner(
                        message: error,
                        cachedAt: model.cachedAt,
                        retry: { Task { await model.load(client: settings.client, carId: settings.carId) } }
                    )
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.top, Theme.Spacing.s)
                }

                if model.points.count > 1 {
                    map
                    sheet
                } else {
                    Spacer(minLength: 0)
                    state
                    Spacer(minLength: 0)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .interactiveBackEnabled()
        .onAppear { chrome.hide() }
        .onDisappear { chrome.show() }
        .task(id: taskKey) {
            await model.load(client: settings.client, carId: settings.carId)
        }
        .onChange(of: model.period) {
            model.customRange = nil
        }
        .sheet(isPresented: $showFilter) {
            HistoryFilterSheet(initial: model.window()) { range in
                model.customRange = range
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.backgroundTop)
        }
    }

    // MARK: Map

    private var map: some View {
        MapSurface(
            content: .tracks(model.segments.map { segment in
                segment.map { $0.mapCoordinate(correction: settings.mapOffsetCorrection) }
            }),
            label: "历史轨迹，\(Fmt.km(model.distanceKm))，\(rangeText)"
        )
        .overlay(alignment: .topLeading) {
            if let cachedAt = model.cachedAt {
                MapOverlayPill(text: "缓存于 \(Fmt.time(cachedAt))", systemImage: "wifi.slash")
                    .padding(Theme.Spacing.m)
            }
        }
    }

    // MARK: Chrome

    private var filters: some View {
        VStack(spacing: Theme.Spacing.s) {
            SegmentedControl(
                options: HistoryViewModel.Period.allCases.map {
                    SegmentOption(value: $0, label: $0.label)
                },
                selection: $model.period
            )

            if let range = model.customRange {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text("\(Fmt.monthDay(range.lowerBound)) – \(Fmt.monthDay(range.upperBound)) · 自定义")
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    Button {
                        model.customRange = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除自定义时间范围")
                }
                .font(.caption2)
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.m)
    }

    @ViewBuilder
    private var state: some View {
        if model.isLoading && model.points.isEmpty {
            Skeleton(height: 320)
                .padding(.horizontal, Theme.Spacing.m)
        } else if model.points.isEmpty, model.error == nil, !model.unauthorized {
            EmptyStateView(
                systemImage: "map",
                title: "该时间段没有位置记录",
                message: "换一个时间段看看。",
                actionTitle: "切换时间段",
                action: { model.period = model.period == .week ? .month : .week }
            )
            .padding(.horizontal, Theme.Spacing.l)
        }
    }

    // MARK: Sheet

    private var sheet: some View {
        VStack(spacing: Theme.Spacing.s) {
            VStack(spacing: Theme.Spacing.m) {
                StatStrip(columns: [
                    (Fmt.km(model.distanceKm), "约轨迹长度"),
                    ("\(model.points.count.formatted())", "采样点"),
                    (rangeText, "时间范围")
                ])

                HStack(spacing: Theme.Spacing.m) {
                    legend(Theme.green, "起点")
                    endLegend
                    legend(Theme.accent, "轨迹")
                    Spacer(minLength: 0)
                    Text("距离为采样点估算")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Theme.Spacing.m)
            .card()

            if settings.mapOffsetCorrection {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(Theme.accent)
                    Text("地图已应用 WGS-84 → GCJ-02 校正，可在设置中关闭。")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(Theme.Spacing.m)
                .glassSurface(.tile)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.m)
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var endLegend: some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Theme.orange)
            Text("终点")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var rangeText: String {
        guard let range = model.range else { return "—" }
        return "\(Fmt.monthDay(range.lowerBound)) – \(Fmt.monthDay(range.upperBound))"
    }
}
