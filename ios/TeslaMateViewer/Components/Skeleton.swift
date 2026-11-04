import SwiftUI

/// C-33 — card-shaped placeholder with a 1.2 s shimmer, shown on first load only.
struct Skeleton: View {
    var height: CGFloat = 96
    var cornerRadius: CGFloat = Theme.Radius.card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.white.opacity(0.06))
            .frame(height: height)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.10), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.5)
                    .offset(x: animating ? proxy.size.width : -proxy.size.width * 0.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    animating = true
                }
            }
            .accessibilityLabel("正在载入")
    }
}
