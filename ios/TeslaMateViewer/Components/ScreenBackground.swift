import SwiftUI

/// Navy gradient with a cyan / purple aurora for the glass surfaces to tint.
/// The top ~120 pt stays neutral so the header never sits on a saturated band.
struct ScreenBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                LinearGradient(
                    colors: [Theme.backgroundTop, Theme.backgroundBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Ellipse()
                    .fill(.white.opacity(0.06))
                    .frame(width: size.width * 1.3, height: size.height * 0.40)
                    .blur(radius: 90)
                    .position(x: size.width * 0.5, y: -size.height * 0.10)

                Ellipse()
                    .fill(Theme.accent.opacity(0.16))
                    .frame(width: size.width * 1.18, height: size.height * 0.46)
                    .blur(radius: 90)
                    .position(x: size.width * 0.16, y: size.height * 0.38)

                Ellipse()
                    .fill(Theme.purple.opacity(0.14))
                    .frame(width: size.width, height: size.height * 0.42)
                    .blur(radius: 90)
                    .position(x: size.width * 0.96, y: size.height * 0.52)

                Ellipse()
                    .fill(Theme.teal.opacity(0.11))
                    .frame(width: size.width * 1.2, height: size.height * 0.50)
                    .blur(radius: 90)
                    .position(x: size.width * 0.5, y: size.height * 1.12)
            }
        }
        .ignoresSafeArea()
    }
}
