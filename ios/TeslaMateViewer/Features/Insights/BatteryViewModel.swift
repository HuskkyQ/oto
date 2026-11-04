import Foundation

/// Backs 电池报告 — `/battery`, capacity and range retention inferred from charges.
@MainActor
final class BatteryViewModel: ObservableObject {
    @Published private(set) var report: BatteryReport?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var unauthorized = false
    @Published private(set) var cachedAt: Date?

    private var loadedCarId: Int?

    var hasSamples: Bool { (report?.sampleCount ?? 0) > 0 }

    func load(client: APIClient?, carId: Int) async {
        guard let client else { return }

        if loadedCarId != carId {
            report = nil
            cachedAt = nil
            loadedCarId = carId
        }

        isLoading = report == nil
        error = nil
        unauthorized = false
        defer { isLoading = false }

        let cacheKey = "battery-\(carId)"

        do {
            let result = try await client.battery(carId: carId)
            report = result
            if result.sampleCount > 0 { ScreenCache.shared.store(result, for: cacheKey) }
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

            if report == nil, let cached = ScreenCache.shared.load(BatteryReport.self, for: cacheKey) {
                report = cached.value
                cachedAt = cached.savedAt
            }
        }
    }
}
