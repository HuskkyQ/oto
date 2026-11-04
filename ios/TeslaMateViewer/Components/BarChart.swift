import Charts
import SwiftUI

struct BarPoint: Identifiable {
    let date: Date
    let value: Double

    var id: Date { date }
}

/// C-26 — rounded bars on a date axis, zero-valued buckets kept so gaps stay gaps.
/// Pinch zooms the time axis, a horizontal drag pans it, and a double tap restores the full range.
struct BarChart: View {
    let title: String
    let unit: String
    let color: Color
    let points: [BarPoint]
    var summary: String?
    var unitWidth: Calendar.Component = .day
    var height: CGFloat = 150

    /// This chart's own window; `nil` shows the whole period. Zooming one card leaves the
    /// others alone, so a reader can compare a different stretch of each metric.
    @State private var visibleRange: ClosedRange<Date>?
    @State private var pinchStart: ClosedRange<Date>?
    @State private var dragStart: ClosedRange<Date>?
    @State private var plotWidth: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(summary ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                chart
                    .onAppear { plotWidth = max(geometry.size.width, 1) }
                    .onChange(of: geometry.size.width) { _, width in
                        plotWidth = max(width, 1)
                    }
                    .simultaneousGesture(panGesture)
                    .simultaneousGesture(zoomGesture)
                    .onTapGesture(count: 2) { visibleRange = nil }
            }
            .frame(height: height)
        }
        .card()
        // A different period or bucket re-scales the axis; keeping the old window would clip it.
        .onChange(of: fullDomain) { _, _ in visibleRange = nil }
    }

    private var chart: some View {
        Chart(points) { point in
            BarMark(
                x: .value("时间", point.date, unit: unitWidth),
                y: .value(title, point.value),
                width: barWidth
            )
            .foregroundStyle(color.gradient)
            .cornerRadius(4)
        }
        // The insets keep the edge bars off the plot edge; the wider right one leaves room for
        // a whole date label instead of the "11…" it truncates to.
        .chartXScale(domain: currentDomain, range: .plotDimension(startPadding: 10, endPadding: 24))
        // A bar whose month straddles the window edge is still drawn, and it is not clipped
        // to the plot, so zooming used to spill bars out over the card.
        .chartPlotStyle { plot in plot.clipped() }
        .chartXAxis {
            AxisMarks(values: unitWidth == .month ? .stride(by: .month) : .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.06))
                if unitWidth == .month {
                    AxisValueLabel(
                        format: .dateTime.month(.abbreviated).locale(Locale(identifier: "zh_CN"))
                    )
                } else if let date = value.as(Date.self) {
                    AxisValueLabel {
                        // Without `fixedSize` a tick on the right edge is given only the padding
                        // to render in and comes out as "10…".
                        Text(Fmt.monthDay(date)).fixedSize()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
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
    }

    // MARK: - Zoom and pan

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? currentDomain
                if pinchStart == nil { pinchStart = start }

                let span = start.upperBound.timeIntervalSince(start.lowerBound) / value.magnification
                visibleRange = window(centeredAt: midpoint(of: start), span: span)
            }
            .onEnded { _ in
                pinchStart = nil
                settle()
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                // Let the page scroll: a mostly vertical drag belongs to the scroll view.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                let start = dragStart ?? currentDomain
                if dragStart == nil { dragStart = start }

                let span = start.upperBound.timeIntervalSince(start.lowerBound)
                let shift = -Double(value.translation.width / max(plotWidth, 1)) * span
                visibleRange = window(centeredAt: midpoint(of: start).addingTimeInterval(shift), span: span)
            }
            .onEnded { _ in
                dragStart = nil
                settle()
            }
    }

    /// Drops a range that has grown back to the full domain, so the axis snaps to the data.
    private func settle() {
        guard let range = visibleRange else { return }
        let full = fullDomain
        if range.upperBound.timeIntervalSince(range.lowerBound)
            >= full.upperBound.timeIntervalSince(full.lowerBound) - 1 {
            visibleRange = nil
        }
    }

    private func window(centeredAt moment: Date, span: TimeInterval) -> ClosedRange<Date> {
        let full = fullDomain
        let fullSpan = full.upperBound.timeIntervalSince(full.lowerBound)
        let width = min(max(span, min(minSpan, fullSpan)), fullSpan)

        var lower = moment.addingTimeInterval(-width / 2)
        if lower < full.lowerBound { lower = full.lowerBound }
        if lower.addingTimeInterval(width) > full.upperBound {
            lower = full.upperBound.addingTimeInterval(-width)
        }
        return lower...lower.addingTimeInterval(width)
    }

    private func midpoint(of range: ClosedRange<Date>) -> Date {
        range.lowerBound.addingTimeInterval(range.upperBound.timeIntervalSince(range.lowerBound) / 2)
    }

    /// Two buckets is the closest zoom that still reads as a chart.
    private var minSpan: TimeInterval {
        (unitWidth == .month ? 62 : 2) * 86_400
    }

    private var currentDomain: ClosedRange<Date> {
        visibleRange ?? fullDomain
    }

    private var fullDomain: ClosedRange<Date> {
        guard let first = points.first?.date, let last = points.last?.date, first <= last else {
            let now = Date()
            return now...now.addingTimeInterval(86_400)
        }

        // A month bucket is a whole month wide: the domain has to cover every month whole,
        // or the last bar is drawn past the plot edge.
        if unitWidth == .month {
            let calendar = Calendar.current
            let start = calendar.dateInterval(of: .month, for: first)?.start ?? first
            let end = calendar.dateInterval(of: .month, for: last)?.end ?? last
            return start...end
        }

        return first...last
    }

    /// A month bucket is a whole month wide, so a short period would otherwise draw two
    /// enormous blocks. Capped in points; dense buckets still scale with the plot.
    private var barWidth: MarkDimension {
        guard plotWidth > 80 else { return .ratio(0.6) }
        let domain = currentDomain
        let visible = points.filter { domain.contains($0.date) }.count
        let slot = (plotWidth - 20) / CGFloat(max(visible, 1))
        return .fixed(min(slot * 0.6, 36))
    }
}
