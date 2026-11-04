import CoreLocation

/// Converts WGS-84 coordinates (what TeslaMate stores) to GCJ-02 (what Amap and
/// Apple Maps use inside mainland China). Outside China the input is returned unchanged.
enum CoordinateTransform {
    private static let a = 6_378_245.0
    private static let ee = 0.006_693_421_622_965_943

    /// The render-time entry point: conversion applies only when the switch is on.
    static func display(_ coordinate: CLLocationCoordinate2D, correction: Bool) -> CLLocationCoordinate2D {
        correction ? gcj02(fromWGS84: coordinate) : coordinate
    }

    static func gcj02(fromWGS84 coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard !isOutsideChina(coordinate) else { return coordinate }

        var dLat = transformLat(coordinate.longitude - 105.0, coordinate.latitude - 35.0)
        var dLon = transformLon(coordinate.longitude - 105.0, coordinate.latitude - 35.0)

        let radLat = coordinate.latitude / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)

        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)

        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + dLat,
            longitude: coordinate.longitude + dLon
        )
    }

    static func isOutsideChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.longitude < 72.004
            || coordinate.longitude > 137.8347
            || coordinate.latitude < 0.8293
            || coordinate.latitude > 55.8271
    }

    private static func transformLat(_ x: Double, _ y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(_ x: Double, _ y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }
}
