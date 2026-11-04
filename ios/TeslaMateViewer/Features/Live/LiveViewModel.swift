import Foundation

@MainActor
final class LiveViewModel: ObservableObject {
    @Published private(set) var live: LiveResponse?
    @Published private(set) var error: String?
    @Published private(set) var unauthorized = false
    @Published private(set) var cachedAt: Date?
    @Published private(set) var isLoading = false

    /// Drops data from the previous car (FR-2.2).
    func reset() {
        live = nil
        error = nil
        unauthorized = false
        cachedAt = nil
        isLoading = false
    }

    func refresh(client: APIClient?, carId: Int) async {
        guard let client else {
            error = "请先在设置中配置服务器和 Token"
            return
        }

        if live == nil { isLoading = true }
        defer { isLoading = false }

        let key = "live-\(carId)"

        do {
            let response = try await client.live(carId: carId)
            live = response
            error = nil
            unauthorized = false
            cachedAt = nil
            ScreenCache.shared.store(response, for: key)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            if error.isUnauthorized {
                unauthorized = true
                self.error = nil
            } else {
                self.error = error.localizedDescription
            }

            if live == nil, let cached = ScreenCache.shared.load(LiveResponse.self, for: key) {
                live = cached.value
                cachedAt = cached.savedAt
            }
        }
    }
}
