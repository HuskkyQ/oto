import Foundation

struct DriveDay: Identifiable {
    let id: Date
    let drives: [Drive]

    var distanceKm: Double {
        drives.reduce(0) { $0 + ($1.distanceKm ?? 0) }
    }
}

@MainActor
final class DrivesViewModel: ObservableObject {
    enum Period: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        case quarter = 90

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .week: return "7 天"
            case .month: return "30 天"
            case .quarter: return "90 天"
            }
        }
    }

    @Published var period: Period = .month
    @Published private(set) var drives: [Drive] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var error: String?
    @Published private(set) var unauthorized = false
    @Published private(set) var cachedAt: Date?
    @Published private(set) var hasMore = true

    private var nextBeforeId: Int?

    var days: [DriveDay] {
        let calendar = Calendar.current
        var order: [Date] = []
        var groups: [Date: [Drive]] = [:]

        for drive in drives {
            let day = calendar.startOfDay(for: drive.startDate)
            if groups[day] == nil { order.append(day) }
            groups[day, default: []].append(drive)
        }

        return order.map { DriveDay(id: $0, drives: groups[$0] ?? []) }
    }

    var totalDistanceKm: Double {
        drives.reduce(0) { $0 + ($1.distanceKm ?? 0) }
    }

    var totalDurationMin: Int {
        drives.reduce(0) { $0 + ($1.durationMin ?? 0) }
    }

    /// Distance over time across the rows on screen — the same figure the summary strip shows.
    var averageSpeedKmh: Double? {
        guard totalDurationMin > 0 else { return nil }
        return totalDistanceKm / (Double(totalDurationMin) / 60)
    }

    private var startDate: Date {
        Calendar.current.date(byAdding: .day, value: -period.rawValue, to: Date()) ?? Date()
    }

    func load(client: APIClient?, carId: Int) async {
        await fetch(client: client, carId: carId, reset: true)
    }

    func loadMore(client: APIClient?, carId: Int) async {
        await fetch(client: client, carId: carId, reset: false)
    }

    private func fetch(client: APIClient?, carId: Int, reset: Bool) async {
        guard let client else {
            error = "请先在设置中配置服务器和 Token"
            return
        }

        if reset {
            // Rows stay on screen until the new period's response lands: emptying the list here
            // flashed the whole page to skeletons on every period switch.
            isLoading = true
            nextBeforeId = nil
            hasMore = true
            error = nil
            unauthorized = false
            cachedAt = nil
        } else {
            guard !isLoading, !isLoadingMore, hasMore else { return }
            isLoadingMore = true
        }

        let requestedPeriod = period
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let response = try await client.drives(
                carId: carId,
                from: startDate,
                to: Date(),
                limit: 100,
                beforeId: nextBeforeId
            )

            guard period == requestedPeriod else { return }

            if reset {
                drives = response.drives
            } else {
                let known = Set(drives.map(\.id))
                drives.append(contentsOf: response.drives.filter { !known.contains($0.id) })
            }
            nextBeforeId = response.nextBeforeId
            hasMore = response.nextBeforeId != nil
            error = nil
            unauthorized = false
            ScreenCache.shared.store(drives, for: cacheKey(carId: carId, period: requestedPeriod))
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            if error.isUnauthorized {
                unauthorized = true
                self.error = nil
            } else {
                self.error = error.localizedDescription
            }

            if reset, drives.isEmpty,
               let cached = ScreenCache.shared.load([Drive].self, for: cacheKey(carId: carId, period: requestedPeriod)) {
                drives = cached.value
                cachedAt = cached.savedAt
                hasMore = false
            }
        }
    }

    private func cacheKey(carId: Int, period: Period) -> String {
        "drives-\(carId)-\(period.rawValue)"
    }
}
