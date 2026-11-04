import MapKit
import SwiftUI

/// C-27 — the only view that instantiates a `Map`.
///
/// Takes already-converted coordinates, fits the camera once with ≥ 12 % padding, and never
/// asks for location. Live passes `follows` and `onPan`; Detail and History leave both alone.
struct MapSurface: View {
    enum Content {
        case track(points: [CLLocationCoordinate2D])
        case tracks([[CLLocationCoordinate2D]])
        case position(CLLocationCoordinate2D, title: String)
    }

    let content: Content
    var height: CGFloat?
    let label: String
    var follows = false
    var recenterToken = 0
    var onPan: (() -> Void)?
    /// False for inline previews: the page scrolls instead of the map panning.
    var interactive = true

    @State private var camera: MapCameraPosition

    init(
        content: Content,
        height: CGFloat? = nil,
        label: String,
        follows: Bool = false,
        recenterToken: Int = 0,
        onPan: (() -> Void)? = nil,
        interactive: Bool = true
    ) {
        self.content = content
        self.height = height
        self.label = label
        self.follows = follows
        self.recenterToken = recenterToken
        self.onPan = onPan
        self.interactive = interactive
        _camera = State(initialValue: .region(Self.fit(for: content)))
    }

    private var points: [CLLocationCoordinate2D] {
        switch content {
        case .track(let points): return points
        case .tracks(let segments): return segments.flatMap { $0 }
        case .position(let coordinate, _): return [coordinate]
        }
    }

    private var singleTitle: String? {
        if case .position(_, let title) = content { return title }
        return nil
    }

    private var region: MKCoordinateRegion {
        Self.fit(for: content)
    }

    /// Fitted from the start, so `.automatic` never gets a chance to override it.
    private static func fit(for content: Content) -> MKCoordinateRegion {
        switch content {
        case .track(let points):
            return MapFitting.region(for: points, minimumSpan: 0.004)
        case .tracks(let segments):
            return MapFitting.region(for: segments.flatMap { $0 }, minimumSpan: 0.004)
        case .position(let coordinate, _):
            return MapFitting.region(for: [coordinate], minimumSpan: 0.01)
        }
    }

    /// Re-fits when the data changes, not on every body evaluation.
    private var fitKey: String {
        guard let first = points.first, let last = points.last else { return "empty" }
        return "\(points.count)-\(first.latitude),\(first.longitude)-\(last.latitude),\(last.longitude)"
    }

    private var refitsOnChange: Bool {
        if case .position = content { return follows }
        return true
    }

    private var interactionModes: MapInteractionModes {
        interactive ? [.pan, .zoom] : []
    }

    var body: some View {
        sized(
            Map(position: $camera, interactionModes: interactionModes) {
                if case .tracks(let segments) = content {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        if segment.count > 1 {
                            MapPolyline(coordinates: segment)
                                .stroke(
                                    Theme.accent,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                                )
                        }
                    }
                    if let start = points.first {
                        Annotation("起点", coordinate: start) { StartDot() }
                    }
                    if let end = points.last {
                        Annotation("终点", coordinate: end) { EndChevron() }
                    }
                } else {
                    TrackLayer(points: points, singleTitle: singleTitle)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .onChange(of: fitKey) {
                guard refitsOnChange else { return }
                camera = .region(region)
            }
            .onChange(of: recenterToken) {
                camera = .region(region)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 6).onChanged { _ in onPan?() },
                including: interactive ? .all : .none
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
        )
    }

    @ViewBuilder
    private func sized(_ map: some View) -> some View {
        if let height {
            map.frame(height: height)
        } else {
            map.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// C-28 — one 3 pt stroke, a filled start dot, a chevron end; a single position becomes a pin.
struct TrackLayer: MapContent {
    let points: [CLLocationCoordinate2D]
    var singleTitle: String?

    var body: some MapContent {
        if points.count > 1 {
            MapPolyline(coordinates: points)
                .stroke(
                    Theme.accent,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )

            if let start = points.first {
                Annotation("起点", coordinate: start) {
                    StartDot()
                }
            }

            if let end = points.last {
                Annotation("终点", coordinate: end) {
                    EndChevron()
                }
            }
        } else if let only = points.first {
            Marker(singleTitle ?? "位置", coordinate: only)
                .tint(Theme.accent)
        }
    }
}

private struct StartDot: View {
    var body: some View {
        Circle()
            .fill(Theme.green)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }
}

/// A chevron rather than a dot, so start and end survive greyscale (FR-9.4).
private struct EndChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(Theme.orange)
            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
    }
}

/// C-29 — a small glass capsule over the map: status, place, or an action.
struct MapOverlayPill: View {
    let text: String
    var systemImage: String?
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { pill }
                .buttonStyle(.plain)
        } else {
            pill
        }
    }

    private var pill: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Theme.glassRim, lineWidth: 1))
        }
    }
}

/// C-30 — C-29 pinned bottom-right, appearing only after a pan.
struct RecenterControl: View {
    let action: () -> Void

    var body: some View {
        MapOverlayPill(text: "回到车辆", systemImage: "scope", action: action)
            .accessibilityLabel("回到车辆位置")
    }
}

enum MapFitting {
    /// A 1.4× span leaves 20 % on every edge, above the 12 % the design requires.
    static func region(
        for points: [CLLocationCoordinate2D],
        minimumSpan: Double
    ) -> MKCoordinateRegion {
        guard let minLat = points.map(\.latitude).min(),
              let maxLat = points.map(\.latitude).max(),
              let minLon = points.map(\.longitude).min(),
              let maxLon = points.map(\.longitude).max()
        else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, minimumSpan),
                longitudeDelta: max((maxLon - minLon) * 1.4, minimumSpan)
            )
        )
    }
}

extension Position {
    func mapCoordinate(correction: Bool) -> CLLocationCoordinate2D {
        GeoPoint(latitude: latitude, longitude: longitude).mapCoordinate(correction: correction)
    }
}

extension GeoPoint {
    /// WGS-84 → GCJ-02 only when the switch is on and the point is inside China.
    func mapCoordinate(correction: Bool) -> CLLocationCoordinate2D {
        let raw = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CoordinateTransform.display(raw, correction: correction)
    }
}
