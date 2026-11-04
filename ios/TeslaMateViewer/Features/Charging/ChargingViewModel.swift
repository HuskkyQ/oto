import Foundation

@MainActor
final class ChargingViewModel: ObservableObject {
    typealias Period = DrivesViewModel.Period

    @Published var period: Period = .month
    @Published private(set) var charges: [ChargingSession] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var error: String?
    @Published private(set) var unauthorized = false
    @Published private(set) var cachedAt: Date?
    @Published private(set) var hasMore = true

    private var nextBeforeId: Int?

    var totalEnergyKwh: Double {
        charges.reduce(0) { $0 + ($1.chargeEnergyAdded ?? 0) }
    }

    var totalCost: Double? {
        let costs = charges.compactMap(\.cost)
        return costs.isEmpty ? nil : costs.reduce(0, +)
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
            let response = try await client.charges(
                carId: carId,
                from: startDate,
                to: Date(),
                limit: 100,
                beforeId: nextBeforeId
            )

            guard period == requestedPeriod else { return }

            if reset {
                charges = response.charges
            } else {
                let known = Set(charges.map(\.id))
                charges.append(contentsOf: response.charges.filter { !known.contains($0.id) })
            }
            nextBeforeId = response.nextBeforeId
            hasMore = response.nextBeforeId != nil
            error = nil
            unauthorized = false
            ScreenCache.shared.store(charges, for: cacheKey(carId: carId, period: requestedPeriod))
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

            if reset, charges.isEmpty,
               let cached = ScreenCache.shared.load([ChargingSession].self, for: cacheKey(carId: carId, period: requestedPeriod)) {
                charges = cached.value
                cachedAt = cached.savedAt
                hasMore = false
            }
        }
    }

    private func cacheKey(carId: Int, period: Period) -> String {
        "charges-\(carId)-\(period.rawValue)"
    }
}
