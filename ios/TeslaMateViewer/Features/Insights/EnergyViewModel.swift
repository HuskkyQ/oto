import Foundation

/// Backs 能耗分析 — `/energy`, grouped by software version, season or outside temperature.
@MainActor
final class EnergyViewModel: ObservableObject {
    enum Grouping: String, CaseIterable, Identifiable {
        case version
        case season
        case temperature

        var id: String { rawValue }

        var label: String {
            switch self {
            case .version: return "软件版本"
            case .season: return "季节"
            case .temperature: return "温度"
            }
        }

        /// Column labels follow the grouping: a "best version" column is meaningless for seasons.
        var bestLabel: String {
            switch self {
            case .version: return "最优版本"
            case .season: return "最优季节"
            case .temperature: return "最优温度"
            }
        }
    }

    @Published var grouping: Grouping = .version
    @Published private(set) var response: EnergyResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var unauthorized = false
    @Published private(set) var cachedAt: Date?

    private var loadedKey: String?

    /// TeslaMate only records versions it saw in `updates`; without them every drive lands in one
    /// bucket, which the page says out loud instead of pretending it has a comparison.
    var hasVersionData: Bool {
        guard grouping == .version, let response else { return true }
        return !(response.groups.count == 1 && response.groups[0].key == "__unknown__")
    }

    var meanWhPerKm: Int? { response?.averageWhPerKm }

    func load(client: APIClient?, carId: Int) async {
        guard let client else { return }

        let grouping = self.grouping
        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -180, to: to) ?? to
        let key = "\(carId)-\(grouping.rawValue)"

        if loadedKey != key {
            response = nil
            cachedAt = nil
            loadedKey = key
        }

        isLoading = response == nil
        error = nil
        unauthorized = false
        defer { isLoading = false }

        let cacheKey = "energy-\(carId)-\(grouping.rawValue)"

        do {
            let result = try await client.energy(
                carId: carId,
                from: from,
                to: to,
                group: grouping.rawValue
            )

            guard self.grouping == grouping else { return }

            response = result
            // Only a real answer replaces the cached one, so an empty window does not erase it.
            if !result.groups.isEmpty { ScreenCache.shared.store(result, for: cacheKey) }
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

            if response == nil, let cached = ScreenCache.shared.load(EnergyResponse.self, for: cacheKey) {
                response = cached.value
                cachedAt = cached.savedAt
            }
        }
    }

    /// Signed difference from the mean, as the mockup's `+3.2%` / `−4.5%` chips.
    func delta(_ group: EnergyGroup) -> Double? {
        guard let mean = meanWhPerKm, mean > 0 else { return nil }
        return (Double(group.whPerKm) - Double(mean)) / Double(mean) * 100
    }

    /// Bars share one scale so their lengths are comparable; the longest reaches 100 %.
    func barFraction(_ group: EnergyGroup) -> Double {
        guard let max = response?.groups.map(\.whPerKm).max(), max > 0 else { return 0 }
        return Double(group.whPerKm) / Double(max)
    }

    func meanFraction() -> Double? {
        guard let mean = meanWhPerKm,
              let max = response?.groups.map(\.whPerKm).max(),
              max > 0
        else { return nil }
        return min(Double(mean) / Double(max), 1)
    }
}
