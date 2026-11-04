import Foundation

/// Backs the Live page's 今日 board and 月度里程 card.
///
/// Two sources, both already in the API: `/stats?bucket=day|month` for the totals and `/states`
/// for the 24-hour band. Energy (kWh / Wh·km⁻¹) is not in `/stats`, so the board does not show it
/// rather than guessing it from a battery-percentage difference.
@MainActor
final class TodayViewModel: ObservableObject {
    @Published private(set) var day: StatsBucket?
    @Published private(set) var slices: [StatusSlice] = []
    @Published private(set) var months: [StatsBucket] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var cachedAt: Date?
    @Published private(set) var unauthorized = false

    private var loadedCarId: Int?

    var monthTotalKm: Double {
        months.reduce(0) { $0 + $1.distanceKm }
    }

    var monthAverageKm: Double {
        months.isEmpty ? 0 : monthTotalKm / Double(months.count)
    }

    var hasRecords: Bool {
        (day?.driveCount ?? 0) > 0 || (day?.chargeCount ?? 0) > 0
    }

    func load(client: APIClient?, carId: Int) async {
        guard let client else { return }

        if loadedCarId != carId {
            day = nil
            slices = []
            months = []
            cachedAt = nil
            loadedCarId = carId
        }

        let calendar = Calendar.current
        let now = Date()
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now

        isLoading = day == nil
        error = nil
        unauthorized = false
        defer { isLoading = false }

        let dayKey = "today-\(carId)-\(Int(dayStart.timeIntervalSince1970))"

        do {
            async let dayStats = client.stats(carId: carId, from: dayStart, to: dayEnd, bucket: "day")
            async let stateList = client.states(carId: carId, from: dayStart, to: now)

            day = try await dayStats.buckets.last
            slices = Self.slices(
                from: try await stateList.states,
                dayStart: dayStart,
                now: now
            )
            cachedAt = nil
            if let day { ScreenCache.shared.store(day, for: dayKey) }
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

            if day == nil, let cached = ScreenCache.shared.load(StatsBucket.self, for: dayKey) {
                day = cached.value
                cachedAt = cached.savedAt
            }
        }

        await loadMonths(client: client, carId: carId, now: now)
    }

    /// Six calendar months ending with the current one, zero-filled so a quiet month is a
    /// short bar rather than a missing column.
    private func loadMonths(client: APIClient, carId: Int, now: Date) async {
        let calendar = Calendar.current
        guard let thisMonth = calendar.dateInterval(of: .month, for: now)?.start,
              let from = calendar.date(byAdding: .month, value: -5, to: thisMonth),
              let to = calendar.date(byAdding: .month, value: 1, to: thisMonth) else { return }

        let key = "months-\(carId)-\(Int(thisMonth.timeIntervalSince1970))"

        do {
            let response = try await client.stats(carId: carId, from: from, to: to, bucket: "month")
            var byMonth: [Date: StatsBucket] = [:]
            for bucket in response.buckets {
                let start = calendar.dateInterval(of: .month, for: bucket.bucket)?.start ?? bucket.bucket
                byMonth[start] = bucket
            }

            var filled: [StatsBucket] = []
            var cursor = from
            while cursor < to, filled.count < 24 {
                filled.append(
                    byMonth[cursor] ?? StatsBucket(
                        bucket: cursor,
                        driveCount: 0,
                        distanceKm: 0,
                        durationMin: 0,
                        chargeCount: 0,
                        chargeEnergyKwh: 0,
                        chargeCost: nil
                    )
                )
                guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = next
            }

            months = filled
            ScreenCache.shared.store(filled, for: key)
        } catch {
            // The month card is secondary: a failure here leaves it off the page, not an error
            // banner over the whole screen.
            if months.isEmpty, let cached = ScreenCache.shared.load([StatsBucket].self, for: key) {
                months = cached.value
            }
        }
    }

    /// States → band slices clipped to the local day. A covering state that began yesterday is
    /// clipped to midnight, and any hole in the table becomes `unknown` instead of collapsing.
    static func slices(from periods: [StatePeriod], dayStart: Date, now: Date) -> [StatusSlice] {
        let end = min(now, dayStart.addingTimeInterval(24 * 60 * 60))
        var result: [StatusSlice] = []
        var cursor = dayStart

        for period in periods.sorted(by: { $0.startDate < $1.startDate }) {
            let start = max(period.startDate, dayStart)
            let finish = min(period.endDate ?? now, end)
            guard finish > start else { continue }

            if start > cursor, let gap = slice("unknown", from: cursor, to: start) {
                result.append(gap)
            }
            if let slice = slice(period.state, from: max(start, cursor), to: finish) {
                result.append(slice)
            }
            cursor = max(cursor, finish)
        }

        if cursor < end, let gap = slice("unknown", from: cursor, to: end) {
            result.append(gap)
        }

        return result
    }

    private static func slice(_ state: String, from: Date, to: Date) -> StatusSlice? {
        let minutes = Int((to.timeIntervalSince(from) / 60).rounded())
        guard minutes > 0 else { return nil }
        return StatusSlice(state: state, minutes: minutes)
    }
}
