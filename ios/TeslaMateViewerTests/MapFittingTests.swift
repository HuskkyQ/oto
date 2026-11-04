import MapKit
import XCTest
@testable import TeslaMate

/// FR-9.3 — the fitted camera leaves ≥ 12 % on every edge.
final class MapFittingTests: XCTestCase {
    private func track(
        lat: ClosedRange<Double>,
        lon: ClosedRange<Double>,
        count: Int = 60
    ) -> [CLLocationCoordinate2D] {
        (0..<count).map { index in
            let t = Double(index) / Double(count - 1)
            return CLLocationCoordinate2D(
                latitude: lat.lowerBound + (lat.upperBound - lat.lowerBound) * t,
                longitude: lon.lowerBound + (lon.upperBound - lon.lowerBound) * t
            )
        }
    }

    /// Padding per edge, as a fraction of the content span.
    private func padding(content: Double, span: Double) -> Double {
        (span - content) / 2 / content
    }

    func testTrackLeavesAtLeast12PercentOnEveryEdge() {
        let points = track(lat: 31.0...31.1, lon: 121.0...121.2)
        let region = MapFitting.region(for: points, minimumSpan: 0.004)

        XCTAssertEqual(region.center.latitude, 31.05, accuracy: 1e-9)
        XCTAssertEqual(region.center.longitude, 121.1, accuracy: 1e-9)
        XCTAssertEqual(region.span.latitudeDelta, 0.14, accuracy: 1e-9)
        XCTAssertEqual(region.span.longitudeDelta, 0.28, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(padding(content: 0.1, span: region.span.latitudeDelta), 0.12)
        XCTAssertGreaterThanOrEqual(padding(content: 0.2, span: region.span.longitudeDelta), 0.12)
    }

    func testTinyTrackUsesTheMinimumSpan() {
        let points = track(lat: 31.2304...31.2305, lon: 121.4737...121.4738)
        let region = MapFitting.region(for: points, minimumSpan: 0.004)

        XCTAssertEqual(region.span.latitudeDelta, 0.004, accuracy: 1e-12)
        XCTAssertEqual(region.span.longitudeDelta, 0.004, accuracy: 1e-12)
    }

    /// A single position gets the wider minimum the surface passes for `.position`.
    func testSinglePositionUsesThePositionMinimumSpan() {
        let point = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
        let region = MapFitting.region(for: [point], minimumSpan: 0.01)

        XCTAssertEqual(region.center.latitude, 31.2304, accuracy: 1e-12)
        XCTAssertEqual(region.center.longitude, 121.4737, accuracy: 1e-12)
        XCTAssertEqual(region.span.latitudeDelta, 0.01, accuracy: 1e-12)
        XCTAssertEqual(region.span.longitudeDelta, 0.01, accuracy: 1e-12)
    }

    /// Repeated points leave a zero-width span; the minimum still applies.
    func testIdenticalPointsStillProduceAUsableRegion() {
        let point = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
        let region = MapFitting.region(for: Array(repeating: point, count: 60), minimumSpan: 0.004)

        XCTAssertEqual(region.span.latitudeDelta, 0.004, accuracy: 1e-12)
        XCTAssertEqual(region.span.longitudeDelta, 0.004, accuracy: 1e-12)
    }

    @MainActor
    func testHistorySeparatesDrivesAndUnknownPoints() throws {
        let json = """
        [
          {"date":"2026-01-01T00:00:00Z","latitude":0,"longitude":0,"drive_id":1},
          {"date":"2026-01-01T00:00:01Z","latitude":0,"longitude":1,"drive_id":1},
          {"date":"2026-01-01T00:00:02Z","latitude":0,"longitude":20,"drive_id":2},
          {"date":"2026-01-01T00:00:03Z","latitude":0,"longitude":21,"drive_id":2},
          {"date":"2026-01-01T00:00:04Z","latitude":0,"longitude":30},
          {"date":"2026-01-01T00:00:05Z","latitude":0,"longitude":40}
        ]
        """
        let points = try JSONDecoder.teslaMate.decode([Position].self, from: Data(json.utf8))
        let segments = HistoryViewModel.segments(for: points)

        XCTAssertEqual(segments.map(\.count), [2, 2, 1, 1])
        XCTAssertEqual(segments[0].map(\.driveId), [1, 1])
        XCTAssertEqual(segments[1].map(\.driveId), [2, 2])
    }

    /// The caller hides the frame on an empty track; the region must still be valid.
    func testEmptyTrackFallsBackToAWorldRegion() {
        let region = MapFitting.region(for: [], minimumSpan: 0.004)

        XCTAssertEqual(region.center.latitude, 0, accuracy: 1e-12)
        XCTAssertEqual(region.center.longitude, 0, accuracy: 1e-12)
        XCTAssertEqual(region.span.latitudeDelta, 1, accuracy: 1e-12)
        XCTAssertEqual(region.span.longitudeDelta, 1, accuracy: 1e-12)
    }
}
