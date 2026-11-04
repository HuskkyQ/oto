import Foundation

/// Backs 停车记录 — `/parking`, gaps between drives and charges over 7, 30 or 90 days.
@MainActor
final class ParkingViewModel: ObservableObject {
    enum Period: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        case quarter = 90

        var id: Int { rawValue }
        var label: String { "\(rawValue) 天" }
    }

    @Published var period: Period = .week
    @Published private(set) var response: ParkingResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var unauthorized = false
    @Published private(set) var cachedAt: Date?

    private var loadedKey: String?

    var sessions: [ParkingSession] { response?.sessions ?? [] }

    func load(client: APIClient?, carId: Int) async {
        guard let client else { return }

        let period = self.period
        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -period.rawValue, to: to) ?? to
        let key = "\(carId)-\(period.rawValue)"

        if loadedKey != key {
            response = nil
            cachedAt = nil
            loadedKey = key
        }

        isLoading = response == nil
        error = nil
        unauthorized = false
        defer { isLoading = false }

        let cacheKey = "parking-\(carId)-\(period.rawValue)"

        do {
            let result = try await client.parking(carId: carId, from: from, to: to)
            guard self.period == period else { return }

            response = result
            if !result.sessions.isEmpty { ScreenCache.shared.store(result, for: cacheKey) }
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

            if response == nil, let cached = ScreenCache.shared.load(ParkingResponse.self, for: cacheKey) {
                response = cached.value
                cachedAt = cached.savedAt
            }
        }
    }
}
