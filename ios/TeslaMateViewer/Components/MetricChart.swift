import Charts
import SwiftUI

struct MetricPoint: Identifiable {
    let date: Date
    let value: Double

    var id: Date { date }
}

struct MetricChart: View {
    let title: String
    let unit: String
    let color: Color
    let points: [MetricPoint]
    var summary: String?
    var xDomain: ClosedRange<Date>?
    var height: CGFloat = 170

    private var headerValue: String {
        if let summary { return summary }
        guard let last = points.last else { return "—" }
        return String(format: "%.1f %@", last.value, unit)
    }

    private var domain: ClosedRange<Date> {
        if let xDomain { return xDomain }
        guard let first = points.first?.date, let last = points.last?.date, first < last else {
            let now = Date()
            return now...now.addingTimeInterval(60)
        }
        return first...last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(headerValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart(points) { point in
                AreaMark(
                    x: .value("时间", point.date),
                    y: .value(title, point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.32), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("时间", point.date),
                    y: .value(title, point.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartXScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: height)
        }
        .card()
    }
}
