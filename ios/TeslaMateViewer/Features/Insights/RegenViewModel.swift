import Foundation

/// Backs 动能回收 — `/regen`, the last seven days of recovered energy.
@MainActor
final class RegenViewModel: ObservableObject {
    @Published private(set) var response: RegenResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var unauthorized = false
    @Published private(set) var cachedAt: Date?

    private var loadedCarId: Int?

    /// Monday through Sunday of the current week. Days the car did not drive are zero, so the
    /// seven columns always mean the same weekdays.
    var weekBars: [MiniBar] {
        let calendar = Calendar.current
        let labels = ["一", "二", "三", "四", "五", "六", "日"]
        let today = calendar.startOfDay(for: Date())

        // `weekday` is 1 = Sunday; shift so Monday is 0.
        let offset = (calendar.component(.weekday, from: today) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -offset, to: today) else { return [] }

        let peaks: [Date: Double] = (response?.days ?? []).reduce(into: [Date: Double]()) { result, day in
            result[calendar.startOfDay(for: day.date)] = day.peakKw
        }

        return (0..<7).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: monday) else { return nil }
            return MiniBar(
                label: labels[index],
                value: peaks[calendar.startOfDay(for: date)] ?? 0,
                highlighted: calendar.isDate(date, inSameDayAs: today)
            )
        }
    }

    /// Newest first, as the API returns them.
    var versions: [RegenVersion] { response?.versions ?? [] }

    func load(client: APIClient?, carId: Int) async {
        guard let client else { return }

        if loadedCarId != carId {
            response = nil
            cachedAt = nil
            loadedCarId = carId
        }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        // A whole week back to the start of today, so the first bar is a full day.
        let from = calendar.date(byAdding: .day, value: -6, to: today) ?? today

        isLoading = response == nil
        error = nil
        unauthorized = false
        defer { isLoading = false }

        let cacheKey = "regen-\(carId)"

        do {
            let result = try await client.regen(carId: carId, from: from, to: now)
            response = result
            if !result.days.isEmpty { ScreenCache.shared.store(result, for: cacheKey) }
            cachedAt = nil
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

            if response == nil, let cached = ScreenCache.shared.load(RegenResponse.self, for: cacheKey) {
                response = cached.value
                cachedAt = cached.savedAt
            }
        }
    }
}
