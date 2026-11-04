import SwiftUI

/// C-16 — equal columns of number + label in one glass strip.
struct StatStrip: View {
    let columns: [(value: String, label: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<columns.count, id: \.self) { index in
                let column = columns[index]

                if index > 0 {
                    Rectangle()
                        .fill(.white.opacity(0.10))
                        .frame(width: 0.5, height: 28)
                }

                VStack(spacing: 2) {
                    Text(column.value)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(column.label)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .glassSurface(.tile)
    }
}
