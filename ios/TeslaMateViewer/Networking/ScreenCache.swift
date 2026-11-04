import Foundation

/// FR-8.2 — the last successful response per screen, kept for the session so a dead
/// network leaves the screen readable and labelled instead of blank.
@MainActor
final class ScreenCache {
    static let shared = ScreenCache()

    private var entries: [String: (value: Any, savedAt: Date)] = [:]

    func store<Value>(_ value: Value, for key: String) {
        entries[key] = (value, Date())
    }

    func load<Value>(_ type: Value.Type, for key: String) -> (value: Value, savedAt: Date)? {
        guard let entry = entries[key], let value = entry.value as? Value else { return nil }
        return (value, entry.savedAt)
    }

    func clear() {
        entries.removeAll()
    }
}
