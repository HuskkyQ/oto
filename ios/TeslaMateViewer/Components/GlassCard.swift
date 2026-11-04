import SwiftUI

enum GlassStyle {
    case card
    case chart
    case tile

    var radius: CGFloat {
        switch self {
        case .card: return Theme.Radius.card
        case .chart, .tile: return Theme.Radius.tile
        }
    }

    var padding: EdgeInsets {
        switch self {
        case .card:
            return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        case .chart:
            return EdgeInsets(top: 14, leading: 16, bottom: 8, trailing: 16)
        case .tile:
            return EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        }
    }

    var soft: Bool {
        if case .card = self { return false }
        return true
    }
}

/// Body gradient, specular rim, inner top highlight and one soft shadow.
struct GlassBackground: View {
    let radius: CGFloat
    var soft: Bool = false
    var tint: Color?

    private var bodyColors: [Color] {
        if let tint {
            return [tint.opacity(0.22), tint.opacity(0.06), .white.opacity(0.04)]
        }
        return soft
            ? [.white.opacity(0.065), .white.opacity(0.018), .white.opacity(0.038)]
            : [.white.opacity(0.10), .white.opacity(0.03), .white.opacity(0.055)]
    }

    private var rimColors: [Color] {
        if let tint {
            return [tint.opacity(0.65), .white.opacity(0.10), .white.opacity(0.03), tint.opacity(0.25)]
        }
        return [.white.opacity(0.50), .white.opacity(0.10), .white.opacity(0.03), .white.opacity(0.20)]
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        ZStack {
            shape.fill(.ultraThinMaterial)
            // The system material carries a neutral grey wash. Rebase it to the app's navy so
            // the surface reads as tinted glass instead of frosted grey.
            shape.fill(Theme.backgroundBottom.opacity(0.42))
            shape.fill(
                LinearGradient(
                    colors: bodyColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: rimColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.18), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, radius)
                .padding(.top, 1)
        }
        .shadow(color: Theme.glassShadow, radius: 17, x: 0, y: 14)
    }
}

struct GlassSurfaceModifier: ViewModifier {
    let style: GlassStyle
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .padding(style.padding)
            .background {
                GlassBackground(radius: style.radius, soft: style.soft, tint: tint)
            }
    }
}

extension View {
    func card(tint: Color? = nil) -> some View {
        modifier(GlassSurfaceModifier(style: .card, tint: tint))
    }

    func glassSurface(_ style: GlassStyle, tint: Color? = nil) -> some View {
        modifier(GlassSurfaceModifier(style: style, tint: tint))
    }
}
