import Foundation

@MainActor
final class DriveDetailViewModel: ObservableObject {
    @Published private(set) var detail: DriveDetailResponse?
    @Published private(set) var error: String?
    @Published private(set) var unauthorized = false
    @Published private(set) var cachedAt: Date?
    @Published private(set) var isLoading = false

    func load(client: APIClient?, carId: Int, driveId: Int) async {
        guard let client else {
            error = "请先在设置中配置服务器和 Token"
            return
        }

        isLoading = true
        unauthorized = false
        defer { isLoading = false }

        let key = "drive-\(carId)-\(driveId)"

        do {
            let response = try await client.drive(carId: carId, driveId: driveId)
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

            if detail == nil, let cached = ScreenCache.shared.load(DriveDetailResponse.self, for: key) {
                detail = cached.value
                cachedAt = cached.savedAt
            }
        }
    }
}
