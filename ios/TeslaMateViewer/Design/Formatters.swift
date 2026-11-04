import Foundation

enum Fmt {
    static func km(_ value: Double?, decimals: Int = 1) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(decimals)f km", value)
    }

    static func kwh(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f kWh", value)
    }

    static func temp(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f°C", value)
    }

    static func percent(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)%"
    }

    static func speed(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value) km/h"
    }

    static func power(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f kW", value)
    }

    static func duration(minutes: Int?) -> String {
        guard let minutes else { return "—" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 { return "\(hours) 小时 \(rest) 分" }
        return "\(rest) 分"
    }

    /// `17h23` / `40 分` — the compact form a legend needs to stay on one line.
    static func durationCompact(minutes: Int?) -> String {
        guard let minutes else { return "—" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 { return rest == 0 ? "\(hours)h" : "\(hours)h\(rest)" }
        return "\(rest) 分"
    }

    /// `3` + `小时 12 分` — the big number and the unit beside it, for a headline.
    static func durationParts(minutes: Int?) -> (value: String, unit: String) {
        guard let minutes else { return ("—", "") }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 { return ("\(hours)", rest == 0 ? "小时" : "小时 \(rest) 分") }
        return ("\(rest)", "分")
    }

    static func money(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value)
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
                .locale(Locale(identifier: "zh_CN"))
        )
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(
            .dateTime.hour().minute().locale(Locale(identifier: "zh_CN"))
        )
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// `10.05` — the app's numeric month/day form; never the locale's `10/05`.
    static func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date)
    }

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM.dd"
        return formatter
    }()

    static func dayTime(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    /// `今天 07:26 – 10:38` — a parking session's window.
    static func rangeLabel(from start: Date, to end: Date) -> String {
        "\(dayLabel(start)) \(time(start)) – \(time(end))"
    }

    /// `今天` / `昨天` / `11月3日`.
    static func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        return monthDayChineseFormatter.string(from: date)
    }

    private static let monthDayChineseFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    /// `11月4日 周三` — the day board's subtitle.
    static func monthDayWeekday(_ date: Date) -> String {
        monthDayWeekdayFormatter.string(from: date)
    }

    /// `11月` — a monthly bar's label.
    static func monthLabel(_ date: Date) -> String {
        monthLabelFormatter.string(from: date)
    }

    /// `2026 年 10 月` — the calendar's title.
    static func monthTitle(_ date: Date) -> String {
        monthTitleFormatter.string(from: date)
    }

    private static let monthDayWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()

    private static let monthLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        return formatter
    }()

    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月"
        return formatter
    }()

    static func state(_ value: String) -> String {
        switch value {
        case "online": return "在线"
        case "offline": return "离线"
        case "asleep": return "休眠"
        default: return value
        }
    }
}
