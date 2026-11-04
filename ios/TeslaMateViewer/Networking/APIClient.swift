import Foundation

struct APIConfiguration {
    let baseURL: URL
    let token: String
}

extension Error {
    var isUnauthorized: Bool {
        guard let apiError = self as? APIError else { return false }
        if case .unauthorized = apiError { return true }
        return false
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case http(status: Int, message: String?)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器响应无效"
        case .unauthorized:
            return "Token 无效或已失效"
        case .http(let status, let message):
            return message ?? "服务器错误（\(status)）"
        case .decoding:
            return "数据格式与 App 不匹配"
        case .transport(let error):
            return Self.message(for: error)
        }
    }

    /// System network errors are not localized for a Chinese-only UI.
    private static func message(for error: Error) -> String {
        guard let urlError = error as? URLError else { return "网络请求失败" }

        switch urlError.code {
        case .notConnectedToInternet:
            return "网络未连接"
        case .timedOut:
            return "请求超时"
        case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost:
            return "无法连接服务器"
        case .appTransportSecurityRequiresSecureConnection:
            return "需要 HTTPS 连接"
        default:
            return "网络请求失败"
        }
    }
}

final class APIClient {
    private struct ErrorBody: Decodable {
        let error: String?
        let code: String?
    }

    private let configuration: APIConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder.teslaMate

    init(configuration: APIConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func cars() async throws -> [Car] {
        try await get("v1/cars", as: CarsResponse.self).cars
    }

    func live(carId: Int) async throws -> LiveResponse {
        try await get("v1/cars/\(carId)/live", as: LiveResponse.self)
    }

    func positions(
        carId: Int,
        from: Date,
        to: Date,
        maxPoints: Int = 1000
    ) async throws -> PositionsResponse {
        try await get(
            "v1/cars/\(carId)/positions",
            query: [
                .init(name: "from", value: Self.dateString(from)),
                .init(name: "to", value: Self.dateString(to)),
                .init(name: "max_points", value: String(maxPoints))
            ],
            as: PositionsResponse.self
        )
    }

    func drives(
        carId: Int,
        from: Date,
        to: Date,
        limit: Int = 100,
        beforeId: Int? = nil
    ) async throws -> DrivesResponse {
        var query: [URLQueryItem] = [
            .init(name: "from", value: Self.dateString(from)),
            .init(name: "to", value: Self.dateString(to)),
            .init(name: "limit", value: String(limit))
        ]
        if let beforeId {
            query.append(.init(name: "before_id", value: String(beforeId)))
        }

        return try await get("v1/cars/\(carId)/drives", query: query, as: DrivesResponse.self)
    }

    func drive(carId: Int, driveId: Int, maxPoints: Int = 1000) async throws -> DriveDetailResponse {
        try await get(
            "v1/cars/\(carId)/drives/\(driveId)",
            query: [.init(name: "max_points", value: String(maxPoints))],
            as: DriveDetailResponse.self
        )
    }

    func charges(
        carId: Int,
        from: Date,
        to: Date,
        limit: Int = 100,
        beforeId: Int? = nil
    ) async throws -> ChargesResponse {
        var query: [URLQueryItem] = [
            .init(name: "from", value: Self.dateString(from)),
            .init(name: "to", value: Self.dateString(to)),
            .init(name: "limit", value: String(limit))
        ]
        if let beforeId { query.append(.init(name: "before_id", value: String(beforeId))) }
        return try await get("v1/cars/\(carId)/charges", query: query, as: ChargesResponse.self)
    }

    func charge(carId: Int, chargeId: Int) async throws -> ChargeDetailResponse {
        try await get("v1/cars/\(carId)/charges/\(chargeId)", as: ChargeDetailResponse.self)
    }

    func states(carId: Int, from: Date, to: Date) async throws -> StatesResponse {
        try await get(
            "v1/cars/\(carId)/states",
            query: [
                .init(name: "from", value: Self.dateString(from)),
                .init(name: "to", value: Self.dateString(to))
            ],
            as: StatesResponse.self
        )
    }

    func updates(carId: Int) async throws -> [SoftwareUpdate] {
        try await get("v1/cars/\(carId)/updates", as: UpdatesResponse.self).updates
    }

    func stats(
        carId: Int,
        from: Date,
        to: Date,
        bucket: String
    ) async throws -> StatsResponse {
        try await get(
            "v1/cars/\(carId)/stats",
            query: [
                .init(name: "from", value: Self.dateString(from)),
                .init(name: "to", value: Self.dateString(to)),
                .init(name: "bucket", value: bucket)
            ],
            as: StatsResponse.self
        )
    }

    /// `group` is `version` | `season` | `temperature`.
    func energy(carId: Int, from: Date, to: Date, group: String) async throws -> EnergyResponse {
        try await get(
            "v1/cars/\(carId)/energy",
            query: [
                .init(name: "from", value: Self.dateString(from)),
                .init(name: "to", value: Self.dateString(to)),
                .init(name: "group", value: group)
            ],
            as: EnergyResponse.self
        )
    }

    func regen(carId: Int, from: Date, to: Date) async throws -> RegenResponse {
        try await get(
            "v1/cars/\(carId)/regen",
            query: [
                .init(name: "from", value: Self.dateString(from)),
                .init(name: "to", value: Self.dateString(to))
            ],
            as: RegenResponse.self
        )
    }

    func parking(carId: Int, from: Date, to: Date) async throws -> ParkingResponse {
        try await get(
            "v1/cars/\(carId)/parking",
            query: [
                .init(name: "from", value: Self.dateString(from)),
                .init(name: "to", value: Self.dateString(to))
            ],
            as: ParkingResponse.self
        )
    }

    func battery(carId: Int) async throws -> BatteryReport {
        try await get("v1/cars/\(carId)/battery", as: BatteryReport.self)
    }

    private static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter.teslaMateFractional.string(from: date)
    }

    private func get<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        as type: T.Type
    ) async throws -> T {
        var url = configuration.baseURL.appendingPathComponent(path)

        if !query.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw APIError.invalidResponse
            }
            components.queryItems = query
            guard let composed = components.url else { throw APIError.invalidResponse }
            url = composed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if http.statusCode == 401 { throw APIError.unauthorized }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw APIError.http(status: http.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
