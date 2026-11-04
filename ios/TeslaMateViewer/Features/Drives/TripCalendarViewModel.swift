import Foundation

/// One day cell of the trip calendar.
struct CalendarDay: Identifiable {
    let id: Date
    let bucket: StatsBucket

    var dayNumber: Int { Calendar.current.component(.day, from: id) }
    var hasDrive: Bool { bucket.driveCount > 0 }
    var hasCharge: Bool { bucket.chargeCount > 0 }
    var isToday: Bool { Calendar.current.isDateInToday(id) }
}

@MainActor
final class TripCalendarViewModel: ObservableObject {
    /// First day of the month on screen.
    @Published private(set) var month: Date
    @Published private(set) var days: [CalendarDay] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var unauthorized = false
    @Published private(set) var cachedAt: Date?

    private let calendar = Calendar.current

    init(month: Date = Date()) {
        self.month = Calendar.current.dateInterval(of: .month, for: month)?.start ?? month
    }

    /// Blank cells before day 1, Monday-first.
    var leadingBlanks: Int {
        let weekday = calendar.component(.weekday, from: month) // 1 = Sunday
        return (weekday + 5) % 7
    }

    var canGoForward: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { return false }
        return next <= (calendar.dateInterval(of: .month, for: Date())?.start ?? Date())
    }

    var title: String { Fmt.monthTitle(month) }

    var totalDistanceKm: Double { days.reduce(0) { $0 + $1.bucket.distanceKm } }
    var totalDriveCount: Int { days.reduce(0) { $0 + $1.bucket.driveCount } }
    var totalDurationMin: Int { days.reduce(0) { $0 + $1.bucket.durationMin } }
    var totalChargeCount: Int { days.reduce(0) { $0 + $1.bucket.chargeCount } }
    var totalEnergyKwh: Double { days.reduce(0) { $0 + $1.bucket.chargeEnergyKwh } }

    func goBack() {
        guard let previous = calendar.date(byAdding: .month, value: -1, to: month) else { return }
        month = previous
    }

    func goForward() {
        guard canGoForward, let next = calendar.date(byAdding: .month, value: 1, to: month) else { return }
        month = next
    }

    func goToCurrentMonth() {
        month = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
    }

    func load(client: APIClient?, carId: Int) async {
        guard let client else {
            error = "请先在设置中配置服务器和 Token"
            return
        }

        let requestedMonth = month
        guard let to = calendar.date(byAdding: .month, value: 1, to: requestedMonth) else { return }

        isLoading = true
        error = nil
        unauthorized = false
        defer { isLoading = false }

        let key = "calendar-\(carId)-\(Int(requestedMonth.timeIntervalSince1970))"

        do {
            // The last day of a month is "today": the window runs to tomorrow, not to now,
            // so today's bucket is not cut in half.
            let response = try await client.stats(
                carId: carId,
                from: requestedMonth,
                to: to,
                bucket: "day"
            )

            guard month == requestedMonth else { return }

            days = Self.grid(response.buckets, month: requestedMonth, calendar: calendar)
            cachedAt = nil
            ScreenCache.shared.store(days, for: key)
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            if error.isUnauthorized {
                unauthorized = true
            } else {
                self.error = error.localizedDescription
            }

            if days.isEmpty, let cached = ScreenCache.shared.load([CalendarDay].self, for: key) {
                days = cached.value
                cachedAt = cached.savedAt
            }
        }
    }

    /// The API returns only days with data; the grid needs every day of the month.
    static func grid(_ buckets: [StatsBucket], month: Date, calendar: Calendar) -> [CalendarDay] {
        var byDay: [Date: StatsBucket] = [:]
        for bucket in buckets {
            byDay[calendar.startOfDay(for: bucket.bucket)] = bucket
        }

        guard let dayCount = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }

        return (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: month) else { return nil }
            let start = calendar.startOfDay(for: date)
            return CalendarDay(
                id: start,
                bucket: byDay[start] ?? StatsBucket(
                    bucket: start,
                    driveCount: 0,
                    distanceKm: 0,
                    durationMin: 0,
                    chargeCount: 0,
                    chargeEnergyKwh: 0,
                    chargeCost: nil
                )
            )
        }
    }
}
