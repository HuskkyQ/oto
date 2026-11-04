import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @Published var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: Keys.baseURL) }
    }

    @Published var carId: Int {
        didSet {
            UserDefaults.standard.set(carId, forKey: Keys.carId)
            // FR-2.2 — the previous car's responses must not come back.
            if oldValue != carId { ScreenCache.shared.clear() }
        }
    }

    @Published var mapOffsetCorrection: Bool {
        didSet { UserDefaults.standard.set(mapOffsetCorrection, forKey: Keys.mapOffset) }
    }

    @Published private(set) var token: String

    /// Set by any screen's 401 banner; MainTabView presents Settings once.
    @Published var wantsSettings = false

    private enum Keys {
        static let baseURL = "teslamate.baseURL"
        static let carId = "teslamate.carId"
        static let mapOffset = "teslamate.mapOffsetCorrection"
    }

    init() {
        let defaults = UserDefaults.standard

        let storedURL = defaults.string(forKey: Keys.baseURL) ?? ""
        baseURLString = storedURL
        carId = defaults.object(forKey: Keys.carId) as? Int ?? 1

        if defaults.object(forKey: Keys.mapOffset) == nil {
            defaults.set(true, forKey: Keys.mapOffset)
        }
        mapOffsetCorrection = defaults.object(forKey: Keys.mapOffset) as? Bool ?? true

        token = TokenStore.load() ?? ""
    }

    var isConfigured: Bool { client != nil }

    var client: APIClient? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil
        else { return nil }

        return APIClient(configuration: APIConfiguration(baseURL: url, token: token))
    }

    /// Commits a validated configuration. The Keychain write happens first, so a
    /// failure leaves the working configuration untouched.
    func apply(baseURLString newURL: String, token newToken: String?, carId newCarId: Int) throws {
        if let newToken {
            try TokenStore.save(newToken)
            token = newToken
        }
        baseURLString = newURL
        carId = newCarId
    }

    func clearToken() {
        TokenStore.delete()
        token = ""
    }
}
