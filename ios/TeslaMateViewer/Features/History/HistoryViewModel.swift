import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    typealias Period = DrivesViewModel.Period

    @Published var period: Period
    /// Set by the filter sheet; overrides `period` until the reader taps a segment again.
    @Published var customRange: ClosedRange<Date>?
    @Published private(set) var points: [Position] = []
    @Published private(set) var range: ClosedRange<Date>?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var unauthorized = false
    @Published private(set) var cachedAt: Date?

    init(period: Period = .month) {
        self.period = period
    }

    var segments: [[Position]] { Self.segments(for: points) }

    static func segments(for points: [Position]) -> [[Position]] {
        var result: [[Position]] = []
        for point in points {
            if let driveId = point.driveId, result.last?.last?.driveId == driveId {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
        }
        return result
    }

    /// Haversine over the points the map draws, not the odometer.
    var distanceKm: Double {
        segments.reduce(0) { total, segment in
            total + zip(segment, segment.dropFirst()).reduce(0) {
                $0 + Self.haversine($1.0.coordinate, $1.1.coordinate)
            }
        }
    }

    /// FR-7.3 — 2 000 points for a short range, 5 000 once it passes a month.
    var maxPoints: Int {
        let (from, to) = window()
        return to.timeIntervalSince(from) > 30 * 24 * 60 * 60 ? 5000 : 2000
    }

    func window() -> (Date, Date) {
        if let customRange { return (customRange.lowerBound, customRange.upperBound) }
        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -period.rawValue, to: to) ?? to
        return (from, to)
    }

    func load(client: APIClient?, carId: Int) async {
        guard let client else {
            error = "请先在设置中配置服务器和 Token"
            return
        }

        let requestedPeriod = period
        let requestedRange = customRange
        let (from, to) = window()
        let maxPoints = self.maxPoints

        // The old track stays until the new period's points arrive; clearing it here flashed the
        // map to a skeleton on every period switch.

        isLoading = true
        error = nil
        unauthorized = false
        defer { isLoading = false }

        let key = "history-\(carId)-\(requestedPeriod.rawValue)-\(from.timeIntervalSince1970)"

        do {
            let response = try await client.positions(
                carId: carId,
                from: from,
                to: to,
                maxPoints: maxPoints
            )

            guard period == requestedPeriod, customRange == requestedRange else { return }

            points = response.points
            range = response.from...response.to
            cachedAt = nil
            ScreenCache.shared.store(Snapshot(points: points, range: range), for: key)
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

            if points.isEmpty, let cached = ScreenCache.shared.load(Snapshot.self, for: key) {
                points = cached.value.points
                range = cached.value.range
                cachedAt = cached.savedAt
            }
        }
    }

    private struct Snapshot {
        let points: [Position]
        let range: ClosedRange<Date>?
    }

    private static func haversine(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let earthRadiusKm = 6_371.0088
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLat = (b.latitude - a.latitude) * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180

        let h = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }
}
