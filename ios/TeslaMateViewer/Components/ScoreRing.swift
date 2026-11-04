import SwiftUI

/// C-42 — a 0–100 score ring with a rating word beside it.
///
/// The split with `BatteryRing` (C-14): that one shows a percentage and colours itself by level;
/// this one shows a score and colours itself by rating. A page that needs "how full" wants C-14;
/// a page that needs "how good, and why" wants this.
struct ScoreRing: View {
    let score: Int
    /// Under the number, e.g. 健康度.
    let caption: String
    /// Beside the ring, e.g. 优秀.
    let verdict: String
    /// One line under the verdict; the reason or the caveat.
    var detail: String?
    var tint: Color?

    private var resolvedTint: Color {
        tint ?? ScoreRing.tint(for: score)
    }

    private var fraction: Double {
        min(max(Double(score) / 100, 0), 1)
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 12)

                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(resolvedTint.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Text("\(score)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(verdict)
                    .font(.headline)
                    .foregroundStyle(resolvedTint)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption) \(score) 分，\(verdict)")
        .accessibilityValue(detail ?? "")
    }

    /// Rating thresholds are the same everywhere, so they live with the component.
    static func tint(for score: Int) -> Color {
        switch score {
        case 90...: return Theme.green
        case 75..<90: return Theme.accent
        case 60..<75: return Theme.orange
        default: return Theme.red
        }
    }
}
