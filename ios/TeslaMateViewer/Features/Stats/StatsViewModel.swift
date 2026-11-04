import Foundation

@MainActor
final class StatsViewModel: ObservableObject {
    typealias Period = DrivesViewModel.Period

    enum Bucket: String, CaseIterable, Identifiable {
        case day
        case month

        var id: String { rawValue }

        var label: String {
            switch self {
            case .day: return "日"
            case .month: return "月"
            }
        }

        var component: Calendar.Component {
            switch self {
            case .day: return .day
            case .month: return .month
            }
        }
    }

    @Published var period: Period = .month
    @Published var bucket: Bucket = .day
    @Published private(set) var buckets: [StatsBucket] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var unauthorized = false
    @Published private(set) var cachedAt: Date?

    private var loadedCarId: Int?

    var totalDistanceKm: Double {
        buckets.reduce(0) { $0 + $1.distanceKm }
    }

    var totalDriveCount: Int {
        buckets.reduce(0) { $0 + $1.driveCount }
    }

    var totalDurationMin: Int {
        buckets.reduce(0) { $0 + $1.durationMin }
    }

    var totalEnergyKwh: Double {
        buckets.reduce(0) { $0 + $1.chargeEnergyKwh }
    }

    var totalCost: Double? {
        let costs = buckets.compactMap(\.chargeCost)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }

    var hasRecords: Bool {
        buckets.contains { $0.driveCount > 0 || $0.chargeCount > 0 }
    }

    var domain: ClosedRange<Date>? {
        guard let first = buckets.first?.bucket, let last = buckets.last?.bucket, first <= last else {
            return nil
        }
        return first...last
    }

    func distancePoints() -> [BarPoint] {
        points(\.distanceKm)
    }

    func energyPoints() -> [BarPoint] {
        points(\.chargeEnergyKwh)
    }

    func durationPoints() -> [BarPoint] {
        buckets.map { BarPoint(date: $0.bucket, value: Double($0.durationMin)) }
    }

    func load(client: APIClient?, carId: Int) async {
        guard let client else {
            error = "请先在设置中配置服务器和 Token"
            return
        }

        // FR-2.2 — a different car starts from an empty chart, not the old car's numbers.
        if loadedCarId != carId {
            buckets = []
            cachedAt = nil
            loadedCarId = carId
        }

        let requestedPeriod = period
        let requestedBucket = bucket
        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -requestedPeriod.rawValue, to: to) ?? to

        isLoading = true
        error = nil
        unauthorized = false
        defer { isLoading = false }

        let key = cacheKey(carId: carId, period: requestedPeriod, bucket: requestedBucket)

        do {
            let response = try await client.stats(
                carId: carId,
                from: from,
                to: to,
                bucket: requestedBucket.rawValue
            )

            guard period == requestedPeriod, bucket == requestedBucket else { return }

            buckets = zeroFilled(response.buckets, from: from, to: to, bucket: requestedBucket)
            cachedAt = nil
            ScreenCache.shared.store(buckets, for: key)
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

            if buckets.isEmpty, let cached = ScreenCache.shared.load([StatsBucket].self, for: key) {
                buckets = cached.value
                cachedAt = cached.savedAt
            }
        }
    }

    private func cacheKey(carId: Int, period: Period, bucket: Bucket) -> String {
        "stats-\(carId)-\(period.rawValue)-\(bucket.rawValue)"
    }

    private func points(_ keyPath: KeyPath<StatsBucket, Double>) -> [BarPoint] {
        buckets.map { BarPoint(date: $0.bucket, value: $0[keyPath: keyPath]) }
    }

    /// The API returns only buckets that contain data; charts need every bucket in the range.
    private func zeroFilled(
        _ buckets: [StatsBucket],
        from: Date,
        to: Date,
        bucket: Bucket
    ) -> [StatsBucket] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: bucket.component, for: from)?.start ?? from
        let end = calendar.dateInterval(of: bucket.component, for: to)?.start ?? to

        var byBucket: [Date: StatsBucket] = [:]
        for item in buckets {
            let key = calendar.dateInterval(of: bucket.component, for: item.bucket)?.start ?? item.bucket
            byBucket[key] = item
        }

        var result: [StatsBucket] = []
        var cursor = start
        while cursor <= end, result.count < 400 {
            result.append(
                byBucket[cursor] ?? StatsBucket(
                    bucket: cursor,
                    driveCount: 0,
                    distanceKm: 0,
                    durationMin: 0,
                    chargeCount: 0,
                    chargeEnergyKwh: 0,
                    chargeCost: nil
                )
            )
            guard let next = calendar.date(byAdding: bucket.component, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
}
