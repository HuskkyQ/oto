import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case testing
        case connected(carCount: Int)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var cars: [Car] = []
    @Published var draftURL = ""
    @Published var draftToken = ""

    private var pending: (url: String, token: String?, carId: Int)?

    var isTesting: Bool { status == .testing }

    func prepareForEditing(baseURL: String) {
        draftURL = baseURL
        draftToken = ""
    }

    func reset() {
        status = .idle
        cars = []
        draftURL = ""
        draftToken = ""
        pending = nil
    }

    func loadCars(client: APIClient?) async {
        guard let client else {
            status = .idle
            return
        }

        status = .testing
        do {
            let fetched = try await client.cars()
            cars = fetched
            status = .connected(carCount: fetched.count)
        } catch {
            status = .failed(Self.message(for: error))
        }
    }

    /// Validates the draft against `GET /v1/cars` and stages it; `commit` applies it.
    func testConnection(settings: SettingsStore, allowsStoredToken: Bool) async -> Bool {
        let urlString = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedToken = draftToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = Self.validatedURL(urlString) else {
            status = .failed("地址无效：需要 http:// 或 https:// 开头并包含主机名")
            return false
        }

        let token: String
        if !typedToken.isEmpty {
            token = typedToken
        } else if allowsStoredToken {
            token = settings.token
        } else {
            status = .failed("请输入 API Token")
            return false
        }

        status = .testing
        let client = APIClient(configuration: APIConfiguration(baseURL: url, token: token))

        do {
            let fetched = try await client.cars()
            guard let first = fetched.first else {
                status = .failed("连接成功，但没有找到车辆")
                return false
            }

            let selected = fetched.contains { $0.id == settings.carId } ? settings.carId : first.id
            pending = (urlString, typedToken.isEmpty ? nil : typedToken, selected)

            cars = fetched
            draftToken = ""
            status = .connected(carCount: fetched.count)
            return true
        } catch {
            status = .failed(Self.message(for: error))
            return false
        }
    }

    /// Applies the staged configuration. A Keychain failure leaves it untouched.
    func commit(settings: SettingsStore) -> Bool {
        guard let pending else { return true }

        do {
            try settings.apply(
                baseURLString: pending.url,
                token: pending.token,
                carId: pending.carId
            )
            self.pending = nil
            return true
        } catch {
            status = .failed(Self.message(for: error))
            return false
        }
    }

    static func validatedURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host,
              !host.isEmpty
        else { return nil }
        return url
    }

    static func message(for error: Error) -> String {
        guard let api = error as? APIError else { return error.localizedDescription }

        switch api {
        case .unauthorized:
            return "Token 无效"
        case .transport(let underlying):
            if let urlError = underlying as? URLError, urlError.code == .timedOut {
                return "无法连接服务器，检查网络和服务器地址"
            }
            return api.errorDescription ?? "请求失败"
        default:
            return api.errorDescription ?? "请求失败"
        }
    }
}
