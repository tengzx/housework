import SwiftUI

enum Calendar2Layout {
    static let dayStart = 0
    static let dayEnd = 24
    static let hourHeight: CGFloat = 64
    static let gutter: CGFloat = 48
    static let estimatedColumnWidth: CGFloat = 112
    static let minimumEventHeight: CGFloat = 14
    static let laneConflictMinimumHeight: CGFloat = 14
    static let midnightCarryoverLaneToleranceMinutes = 15
    static let fullWidthMidnightSleepMinimumMinutes = 180
    static let hours = Array(dayStart...dayEnd)
    static var gridHeight: CGFloat { CGFloat(dayEnd - dayStart) * hourHeight }
}

enum Calendar2Style {
    static let bg       = Color(hex: "F5F6F8")
    static let sheet    = Color(hex: "FFFFFF")
    static let surface  = Color(hex: "FFFFFF")
    static let surface2 = Color(hex: "F0F1F4")
    static let line     = Color(hex: "E4E6EB")
    static let line2    = Color(hex: "E4E6EB")
    static let gridLine = Color(hex: "E4E6EB")
    static let accent   = Color(hex: "0A84FF")
    static let text     = Color(hex: "1A1C20")
    static let muted    = Color(hex: "8A8F9C")
    static let faint    = Color(hex: "A0A5AE")
    static let text2    = Color(hex: "6F7480")
}

enum Calendar2Format {
    static func day(offset: Int) -> Date {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today
    }

    static func dayOffset(for date: Date) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: date)
        return Calendar.current.dateComponents([.day], from: today, to: target).day ?? 0
    }

    static func date(dayOffset: Int, minute: Int) -> Date {
        let base = day(offset: dayOffset)
        return Calendar.current.date(
            bySettingHour: minute / 60,
            minute: minute % 60,
            second: 0,
            of: base
        ) ?? base
    }

    static func month(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate(
            L10n.currentLanguage == .en ? "MMM" : "M"
        )
        return formatter.string(from: date)
    }

    static func weekday(_ date: Date) -> String {
        let weekdayIndex = Calendar.current.component(.weekday, from: date)
        let keys = [
            "calendar.weekday.sun",
            "calendar.weekday.mon",
            "calendar.weekday.tue",
            "calendar.weekday.wed",
            "calendar.weekday.thu",
            "calendar.weekday.fri",
            "calendar.weekday.sat"
        ]
        return L10n.tr(keys[max(0, min(weekdayIndex - 1, keys.count - 1))])
    }

    static func shortRange(_ offsets: [Int]) -> String {
        guard let first = offsets.first, let last = offsets.last else { return "" }
        let start = day(offset: first)
        let end = day(offset: last)
        let formatter = DateIntervalFormatter()
        formatter.locale = L10n.locale
        formatter.dateTemplate = L10n.currentLanguage == .en ? "MMM d" : "Md"
        return formatter.string(from: start, to: end)
    }

    static func clock(_ minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }

    static func date(fromMinute minuteOfDay: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    static func minute(fromDate date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func segmentationEnd(start: Date, end: Date) -> Date {
        guard end > start else { return start }
        let calendar = Calendar.current
        if calendar.startOfDay(for: end) == end {
            return end.addingTimeInterval(-1)
        }
        return end
    }

    static func defaultStartMinute(date: Date = Date()) -> Int {
        let minute = minute(fromDate: date)
        let rounded = (minute / 15) * 15
        return min(max(rounded, Calendar2Layout.dayStart * 60), Calendar2Layout.dayEnd * 60 - 30)
    }

    static func apiDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func apiDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter.string(from: date)
    }

    static func parseAPIDate(_ value: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) { return date }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: value) { return date }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "Invalid date: \(value)")
        )
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 { return L10n.tr("calendar.duration.hour_minute", hours, mins) }
        if hours > 0 { return L10n.tr("calendar.duration.hour_only", hours) }
        return L10n.tr("calendar.duration.minute_only", mins)
    }
}

struct Calendar2PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}
