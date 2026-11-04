import SwiftUI

/// C-07 — "11月1日 周六 · 4.1 km", pinned above its day's rows.
struct StickyDayHeader: View {
    let date: Date
    let distanceKm: Double

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()

    var body: some View {
        HStack {
            Text(Self.formatter.string(from: date))
            Spacer()
            Text(Fmt.km(distanceKm))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.s)
    }
}
