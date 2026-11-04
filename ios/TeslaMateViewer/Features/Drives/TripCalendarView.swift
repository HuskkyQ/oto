import SwiftUI

/// 行程日历 — one month of `/stats?bucket=day` as a grid, with that month's totals above it.
struct TripCalendarView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var chrome: TabBarChrome
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = TripCalendarViewModel()

    private var taskKey: String {
        "\(settings.carId)-\(model.month.timeIntervalSince1970)"
    }

    var body: some View {
        ScreenScaffold(
            title: "行程日历",
            backAction: { dismiss() },
            actions: [HeaderAction("calendar", label: "回到本月") { model.goToCurrentMonth() }]
        ) {
            VStack(spacing: Theme.Spacing.m) {
                if model.unauthorized {
                    AuthBanner()
                } else if let error = model.error {
                    ErrorBanner(
                        message: error,
                        cachedAt: model.cachedAt,
                        retry: { Task { await load() } }
                    )
                }

                monthHeader
                summary
                grid
            }
            .padding(Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .toolbar(.hidden, for: .navigationBar)
        .interactiveBackEnabled()
        .onAppear { chrome.hide() }
        .onDisappear { chrome.show() }
        .task(id: taskKey) { await load() }
    }

    private func load() async {
        await model.load(client: settings.client, carId: settings.carId)
    }

    // MARK: - Sections

    private var monthHeader: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button {
                model.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上个月")

            VStack(spacing: 2) {
                Text(model.title)
                    .font(.headline)
                Text("月度汇总")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                model.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canGoForward)
            .opacity(model.canGoForward ? 1 : 0.35)
            .accessibilityLabel("下个月")
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private var summary: some View {
        VStack(spacing: Theme.Spacing.s) {
            StatStrip(columns: [
                (Fmt.km(model.totalDistanceKm), "里程"),
                ("\(model.totalDriveCount) 次", "行程"),
                (Fmt.duration(minutes: model.totalDurationMin), "驾驶时长")
            ])
            StatStrip(columns: [
                ("\(model.totalChargeCount) 次", "充电"),
                (Fmt.kwh(model.totalEnergyKwh), "充入电量")
            ])
        }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: 0) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity)
                }
            }

            if model.isLoading && model.days.isEmpty {
                Skeleton(height: 260)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                    spacing: 6
                ) {
                    ForEach(0..<model.leadingBlanks, id: \.self) { _ in
                        Color.clear.frame(height: 44)
                    }

                    ForEach(model.days) { day in
                        CalendarCell(day: day)
                    }
                }
            }

            HStack(spacing: Theme.Spacing.l) {
                legend(Theme.accent, "有行程")
                legend(Theme.green, "有充电")
                Spacer(minLength: 0)
                Text("数字为当日里程（km）")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textFaint)
            }

            Text("平均能耗需要功率积分，首版不显示，避免与 TeslaMate 口径不一致。")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textFaint)
        }
        .card()
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

private struct CalendarCell: View {
    let day: CalendarDay

    var body: some View {
        VStack(spacing: 3) {
            Text("\(day.dayNumber)")
                .font(.system(size: 11, weight: day.isToday ? .bold : .regular))
                .foregroundStyle(day.isToday ? Theme.accent : Theme.textPrimary)

            HStack(spacing: 2) {
                if day.hasDrive { mark(Theme.accent) }
                if day.hasCharge { mark(Theme.green) }
            }
            .frame(height: 4)

            Text(day.bucket.distanceKm > 0 ? "\(Int(day.bucket.distanceKm.rounded()))" : " ")
                .font(.system(size: 9))
                .foregroundStyle(Theme.textFaint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            day.isToday ? Theme.accent.opacity(0.14) : .clear,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func mark(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 4, height: 4)
    }

    private var accessibilityLabel: String {
        var parts = ["\(day.dayNumber) 日"]
        if day.hasDrive { parts.append("\(day.bucket.driveCount) 次行程") }
        if day.hasCharge { parts.append("\(day.bucket.chargeCount) 次充电") }
        if day.bucket.distanceKm > 0 {
            parts.append(Fmt.km(day.bucket.distanceKm))
        }
        return parts.joined(separator: "，")
    }
}
