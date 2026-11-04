import MapKit
import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var chrome: TabBarChrome
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = LiveViewModel()
    @StateObject private var today = TodayViewModel()
    @State private var loadedCarId: Int?
    @State private var showMap = false
    @State private var showSettings = false
    @State private var showCalendar = false

    private var values: LiveValues? { model.live?.values }
    private var car: Car? { model.live?.car }

    var body: some View {
        NavigationStack {
            ScreenScaffold(
                title: car?.displayName ?? "实时",
                actions: [
                    HeaderAction("arrow.clockwise", label: "刷新") {
                        guard !model.isLoading else { return }
                        Task { await refresh() }
                    },
                    HeaderAction("gearshape", label: "设置") {
                        showSettings = true
                    }
                ],
                onRefresh: {
                    await refresh()
                    await loadToday()
                }
            ) {
                VStack(spacing: 16) {
                    if model.unauthorized {
                        AuthBanner()
                    } else if let error = model.error {
                        ErrorBanner(
                            message: error,
                            cachedAt: model.cachedAt,
                            retry: { Task { await refresh() } }
                        )
                    }

                    if model.live == nil && model.isLoading {
                        VStack(spacing: 16) {
                            Skeleton(height: 96)
                            Skeleton(height: 180)
                            Skeleton(height: 96)
                        }
                    } else if let live = model.live {
                        freshness(live)
                        header(live)
                        TodayBoard(
                            day: today.day,
                            slices: today.slices,
                            isLoading: today.isLoading,
                            error: today.error,
                            onOpenCalendar: { showCalendar = true },
                            onRetry: { Task { await loadToday() } }
                        )
                        batteryCard(live)
                        if !today.months.isEmpty {
                            MonthMileageCard(months: today.months)
                        }
                        chargingCard
                        mapCard
                        statusGrid(live)
                        climateCard
                        vehicleCard(live)
                        routeCard
                    } else if model.unauthorized {
                        EmptyStateView(
                            systemImage: "key.slash",
                            title: "无法读取实时数据",
                            message: "Token 无效或已失效。",
                            actionTitle: "去设置",
                            action: { settings.wantsSettings = true }
                        )
                    } else {
                        EmptyStateView(
                            systemImage: "bolt.slash",
                            title: "暂无实时数据",
                            message: "确认 API 服务、MQTT 和车辆连接正常。",
                            actionTitle: "重试",
                            action: { Task { await refresh() } }
                        )
                    }
                }
                .padding(16)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showSettings) {
                SettingsView(isOnboarding: false, onBack: { showSettings = false })
                    .contentMargins(.bottom, 0, for: .scrollContent)
                    .onAppear { chrome.hide() }
                    .onDisappear { chrome.show() }
            }
            .navigationDestination(isPresented: $showCalendar) {
                TripCalendarView()
            }
            .navigationDestination(isPresented: $showMap) {
                if let point = values?.coordinate {
                    LiveMapView(
                        coordinate: point.mapCoordinate(correction: settings.mapOffsetCorrection),
                        title: car?.name ?? "车辆",
                        timestamp: model.live?.lastPositionAt ?? model.live?.receivedAt
                    )
                }
            }
            .task(id: pollingKey) { await poll() }
            .task(id: todayKey) { await loadToday() }
        }
    }

    private var pollingKey: String {
        "\(settings.carId)-\(scenePhase == .active)"
    }

    /// Re-evaluated every poll, so the day board rolls over at local midnight on its own.
    private var todayKey: String {
        "\(settings.carId)-\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)"
    }

    private func loadToday() async {
        await today.load(client: settings.client, carId: settings.carId)
    }

    private func poll() async {
        if loadedCarId != settings.carId {
            model.reset()
            loadedCarId = settings.carId
        }
        guard scenePhase == .active else { return }
        // FR-8.3 — a 401 is not retried; the banner is the only thing left to act on.
        while !Task.isCancelled && scenePhase == .active && !model.unauthorized {
            await refresh()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    private func refresh() async {
        await model.refresh(client: settings.client, carId: settings.carId)
    }

    // MARK: - Sections

    /// FR-8.1 — stale data is labelled in orange; a sleeping car gets a neutral line instead.
    @ViewBuilder
    private func freshness(_ live: LiveResponse) -> some View {
        if values?.state == "asleep" {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(.secondary)
                Text("车辆休眠 · 数据停在 \(Fmt.dateTime(live.receivedAt ?? live.lastPositionAt))")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .glassSurface(.tile)
        } else if live.stale || !live.mqttConnected {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(Theme.orange)
                Text(live.mqttConnected ? "数据已过期，展示最后已知状态" : "MQTT 未连接，展示最后已知状态")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Theme.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func header(_ live: LiveResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                StateBadge(state: values?.state)
                Spacer()
                Text(Fmt.relative(live.receivedAt ?? live.lastPositionAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("live.lastUpdated")
            }
        }
        .card()
    }

    private func batteryCard(_ live: LiveResponse) -> some View {
        HStack(spacing: 22) {
            BatteryRing(
                level: values?.batteryLevel,
                isCharging: values?.chargingState == "Charging"
            )

            VStack(alignment: .leading, spacing: 10) {
                DetailRow(title: "理想续航", value: Fmt.km(values?.idealBatteryRangeKm))
                DetailRow(title: "额定续航", value: Fmt.km(values?.ratedBatteryRangeKm))
                DetailRow(title: "估算续航", value: Fmt.km(values?.estBatteryRangeKm))
                DetailRow(title: "充电功率", value: Fmt.power(values?.chargerPower))
                DetailRow(title: "充电电流", value: values?.chargerActualCurrent.map { "\($0) A" } ?? "—")
                DetailRow(title: "充电电压", value: values?.chargerVoltage.map { "\($0) V" } ?? "—")
            }
        }
        .card()
    }

    /// FR-3.3 — only while charging, between the battery and the map.
    @ViewBuilder
    private var chargingCard: some View {
        if values?.chargingState == "Charging" {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "充电中")

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "充电功率", value: Fmt.power(values?.chargerPower))
                    StatTile(title: "已充入", value: Fmt.kwh(values?.chargeEnergyAdded))
                    StatTile(title: "电量", value: chargingSoc)
                    StatTile(title: "预计充满", value: timeToFull)
                }
            }
            .card()
        }
    }

    private var chargingSoc: String {
        guard let level = values?.batteryLevel else { return "—" }
        guard let limit = values?.chargeLimitSoc else { return "\(level)%" }
        return "\(level)% → \(limit)%"
    }

    /// `time_to_full_charge` is in hours.
    private var timeToFull: String {
        guard let hours = values?.timeToFullCharge else { return "—" }
        return Fmt.duration(minutes: Int((hours * 60).rounded()))
    }

    @ViewBuilder
    private var mapCard: some View {
        if let point = values?.coordinate {
            let coordinate = point.mapCoordinate(correction: settings.mapOffsetCorrection)
            let coordinates = String(format: "%.5f, %.5f", point.latitude, point.longitude)
            let title = car?.name ?? "车辆"

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(title: "车辆位置")
                    Spacer()
                    Text(coordinates)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // A preview only: the page scrolls here, and tapping opens the full map.
                Button {
                    showMap = true
                } label: {
                    MapSurface(
                        content: .position(coordinate, title: title),
                        height: 220,
                        label: "车辆最后位置，\(coordinates)",
                        interactive: false
                    )
                    .overlay(alignment: .topLeading) {
                        if let live = model.live {
                            MapOverlayPill(
                                text: "最后位置 · \(Fmt.time(live.lastPositionAt ?? live.receivedAt))",
                                systemImage: "clock"
                            )
                            .padding(10)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 26, height: 26)
                            .background { Circle().fill(.ultraThinMaterial) }
                            .overlay { Circle().strokeBorder(Theme.glassRim, lineWidth: 1) }
                            .padding(10)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开全屏地图")

                if let geofence = values?.geofence, !geofence.isEmpty {
                    DetailRow(title: "地理围栏", value: geofence)
                }
                DetailRow(title: "海拔", value: values?.elevation.map { "\($0) m" } ?? "—")
                DetailRow(title: "方向", value: values?.heading.map { "\($0)°" } ?? "—")
            }
            .card()
        }
    }

    private func statusGrid(_ live: LiveResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "状态")

            SecurityRow(values: values)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(title: "速度", value: Fmt.speed(values?.speed.map { Int($0.rounded()) }))
                StatTile(title: "功率", value: Fmt.power(values?.power))
                StatTile(title: "里程", value: Fmt.km(values?.odometer))
                StatTile(title: "挡位", value: shiftLabel)
            }
        }
        .card()
    }

    private var climateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "空调")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(title: "车内温度", value: Fmt.temp(values?.insideTemp))
                StatTile(title: "车外温度", value: Fmt.temp(values?.outsideTemp))
                StatTile(title: "设定温度", value: Fmt.temp(values?.driverTempSetting))
                StatTile(title: "空调", value: values?.isClimateOn == true ? "开启" : "关闭")
                StatTile(title: "除霜", value: values?.isFrontDefrosterOn == true ? "前挡" : (values?.isRearDefrosterOn == true ? "后挡" : "关闭"))
                StatTile(title: "风扇", value: values?.fanStatus.map { "\($0)" } ?? "—")
            }
        }
        .card()
    }

    private func vehicleCard(_ live: LiveResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "车辆")
            DetailRow(title: "软件版本", value: values?.version ?? "—")
            DetailRow(title: "车型", value: car?.marketingName ?? car?.trimBadging ?? car?.model ?? "—")
            DetailRow(title: "状态", value: values?.stateLabel ?? "—")
            DetailRow(title: "状态起始", value: Fmt.relative(live.lastPositionAt))
            DetailRow(title: "胎压 前左", value: pressure(values?.tpmsPressureFl))
            DetailRow(title: "胎压 前右", value: pressure(values?.tpmsPressureFr))
            DetailRow(title: "胎压 后左", value: pressure(values?.tpmsPressureRl))
            DetailRow(title: "胎压 后右", value: pressure(values?.tpmsPressureRr))
        }
        .card()
    }

    @ViewBuilder
    private var routeCard: some View {
        if let route = values?.activeRoute, route.destination != nil {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "导航")
                DetailRow(title: "目的地", value: route.destination ?? "—")
                DetailRow(
                    title: "预计到达",
                    value: route.minutesToArrival.map {
                        Fmt.dateTime(Date().addingTimeInterval($0 * 60))
                    } ?? "—"
                )
                DetailRow(title: "剩余距离", value: Fmt.km(route.milesToArrival.map { $0 * 1.60934 }))
                DetailRow(
                    title: "预计耗时",
                    value: route.minutesToArrival.map {
                        Fmt.duration(minutes: Int(($0 * 60).rounded()))
                    } ?? "—"
                )
            }
            .card()
        }
    }

    // MARK: - Helpers

    private var shiftLabel: String {
        switch values?.shiftState {
        case "P": return "P 驻车"
        case "R": return "R 倒挡"
        case "N": return "N 空挡"
        case "D": return "D 前进"
        default: return "—"
        }
    }

    private func pressure(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f psi", value)
    }
}

private extension GeoPoint {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct BatteryRing: View {
    let level: Int?
    let isCharging: Bool

    private var fraction: Double {
        Double(level ?? 0) / 100
    }

    private var tint: Color {
        guard let level else { return .gray }
        if level <= 20 { return Theme.red }
        if level <= 40 { return Theme.orange }
        return Theme.green
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 12)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.green)
                }
                Text(level.map { "\($0)%" } ?? "—")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("电量")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 116, height: 116)
        .animation(.easeInOut(duration: 0.4), value: fraction)
    }
}


/// FR-3.5 — four booleans on one line; any open state turns orange and makes the line expandable.
private struct SecurityRow: View {
    let values: LiveValues?

    @State private var expanded = false

    private var unlocked: Bool { values?.locked == false }
    private var sentry: Bool { values?.sentryMode == true }
    private var doorsOpen: Bool { values?.doorsOpen == true }
    private var windowsOpen: Bool { values?.windowsOpen == true }
    private var trunkOpen: Bool { values?.trunkOpen == true }
    private var frunkOpen: Bool { values?.frunkOpen == true }

    private var hasOpen: Bool { unlocked || doorsOpen || windowsOpen || trunkOpen || frunkOpen }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasOpen {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    row
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("安防")
                .accessibilityValue("有未关闭的项目")
                .accessibilityHint("展开详情")
            } else {
                row
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("安防")
                    .accessibilityValue("全部正常")
            }

            if expanded {
                details
            }
        }
    }

    private var row: some View {
        HStack(spacing: Theme.Spacing.l) {
            item("lock.fill", unlocked ? "未锁" : "已锁", alert: unlocked)
            item(
                sentry ? "shield.fill" : "shield.slash.fill",
                sentry ? "哨兵开" : "哨兵关",
                alert: false
            )
            item(
                doorsOpen ? "door.left.hand.open" : "door.left.hand.closed",
                doorsOpen ? "门开" : "门关",
                alert: doorsOpen
            )
            item(
                windowsOpen ? "window.vertical.open" : "window.vertical.closed",
                windowsOpen ? "窗开" : "窗关",
                alert: windowsOpen
            )

            Spacer(minLength: 0)

            if hasOpen {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.orange)
            }
        }
    }

    private func item(_ symbol: String, _ label: String, alert: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(label)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(alert ? Theme.orange : Theme.textSecondary)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailRow(title: "行李厢", value: trunkOpen ? "开启" : "关闭")
            DetailRow(title: "前备厢", value: frunkOpen ? "开启" : "关闭")
        }
    }
}
