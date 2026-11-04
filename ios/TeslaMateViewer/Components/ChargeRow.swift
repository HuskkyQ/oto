import SwiftUI

/// C-23 — station and time, SoC bar with kWh, duration, temperature and cost.
struct ChargeRow: View {
    let charge: ChargingSession

    private var costText: String {
        guard let cost = charge.cost else { return "费用未记录" }
        return "¥\(Fmt.money(cost))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: 4) {
                Text(Fmt.dateTime(charge.startDate))
                Text("·")
                Text(charge.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)

            HStack(spacing: Theme.Spacing.l) {
                SoCBar(start: charge.startBatteryLevel, end: charge.endBatteryLevel)
                Text(Fmt.kwh(charge.chargeEnergyAdded))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }

            HStack(spacing: Theme.Spacing.s) {
                Text("\(Fmt.duration(minutes: charge.durationMin)) · 车外 \(Fmt.temp(charge.outsideTempAvg))")
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(costText)
                    .foregroundStyle(charge.cost == nil ? Theme.textSecondary : Theme.textPrimary)
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}
