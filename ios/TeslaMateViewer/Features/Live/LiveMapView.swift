import MapKit
import SwiftUI

/// Full-screen vehicle map, pushed from the Live card. The card itself no longer pans.
struct LiveMapView: View {
    let coordinate: CLLocationCoordinate2D
    let title: String
    let timestamp: Date?

    @EnvironmentObject private var chrome: TabBarChrome
    @Environment(\.dismiss) private var dismiss
    @State private var following = true
    @State private var recenterToken = 0

    var body: some View {
        ZStack {
            MapSurface(
                content: .position(coordinate, title: title),
                label: "车辆位置地图",
                follows: following,
                recenterToken: recenterToken,
                onPan: { following = false }
            )
            .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background { Circle().fill(.ultraThinMaterial) }
                    .overlay { Circle().strokeBorder(Theme.glassRim, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
        }
        .overlay(alignment: .bottomLeading) {
            if let timestamp {
                MapOverlayPill(
                    text: "最后位置 · \(Fmt.time(timestamp))",
                    systemImage: "clock"
                )
                .padding(Theme.Spacing.l)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !following {
                RecenterControl {
                    following = true
                    recenterToken += 1
                }
                .padding(Theme.Spacing.l)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .interactiveBackEnabled()
        .onAppear { chrome.hide() }
        .onDisappear { chrome.show() }
    }
}
