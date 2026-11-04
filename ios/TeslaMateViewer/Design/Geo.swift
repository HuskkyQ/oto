import Foundation

enum Geo {
    static func distanceKm(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let earthRadius = 6_371.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180

        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    static func distanceKm(_ points: [GeoPoint]) -> Double {
        guard points.count > 1 else { return 0 }

        var total = 0.0
        for index in 1..<points.count {
            total += distanceKm(points[index - 1], points[index])
        }
        return total
    }
}
