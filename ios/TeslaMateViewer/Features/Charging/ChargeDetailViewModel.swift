import Foundation

@MainActor
final class ChargeDetailViewModel: ObservableObject {
    @Published private(set) var detail: ChargeDetailResponse?
    @Published private(set) var error: String?
    @Published private(set) var unauthorized = false
    @Published private(set) var cachedAt: Date?
    @Published private(set) var isLoading = false

    func load(client: APIClient?, carId: Int, chargeId: Int) async {
        guard let client else {
            error = "请先在设置中配置服务器和 Token"
            return
        }

        isLoading = true
        unauthorized = false
        defer { isLoading = false }

        let key = "charge-\(carId)-\(chargeId)"

        do {
            let response = try await client.charge(carId: carId, chargeId: chargeId)
            detail = response
            error = nil
            cachedAt = nil
            ScreenCache.shared.store(response, for: key)
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

            if detail == nil, let cached = ScreenCache.shared.load(ChargeDetailResponse.self, for: key) {
                detail = cached.value
                cachedAt = cached.savedAt
            }
        }
    }
}
