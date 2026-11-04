import SwiftUI

/// C-22 — times, rail, places, distance and duration.
struct TripRow: View {
    let drive: Drive

    private var startTime: String {
        drive.startDate.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))
    }

    private var endTime: String {
        (drive.endDate ?? drive.startDate)
            .formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))
    }

    /// 均速 and the battery drop on the left, 达成率 on the right — both optional, because a
    /// drive whose data is incomplete says nothing rather than "— · —".
    private var metaText: String {
        var parts: [String] = []
        if let speed = drive.averageSpeedKmh {
            parts.append("均速 \(Int(speed.rounded())) km/h")
        }
        if let transition = drive.batteryTransition {
            parts.append(transition)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            legs

            if !metaText.isEmpty || drive.achievementPercent != nil {
                HStack(spacing: 6) {
                    Text(metaText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 4)

                    if let achievement = drive.achievementPercent {
                        Text("达成率 \(achievement)%")
                            .font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary.opacity(0.78))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.08), in: Capsule())
                    }
                }
                .padding(.leading, 80)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var legs: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(startTime)
                Spacer(minLength: 0)
                Text(endTime)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 46)

            VStack(spacing: 0) {
                dot(Theme.green)
                Rectangle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                dot(Theme.orange)
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 0) {
                Text(drive.startTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(drive.endTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.s)

            VStack(alignment: .trailing, spacing: 0) {
                Text(Fmt.km(drive.distanceKm))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Text(Fmt.duration(minutes: drive.durationMin))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(height: 64)
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color.opacity(0.12))
            .frame(width: 18, height: 18)
            .overlay {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
            }
    }
}
