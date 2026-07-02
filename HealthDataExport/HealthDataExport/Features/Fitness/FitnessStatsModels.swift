import Foundation

// MARK: - Strength volume stats domain

enum FitnessStrengthVolumeRange: String, CaseIterable, Identifiable {
    case week = "7d"
    case month = "30d"
    case year = "1y"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "周"
        case .month: return "月"
        case .year: return "年"
        }
    }

    var subtitle: String {
        switch self {
        case .week: return "按周统计"
        case .month: return "按月统计"
        case .year: return "按年统计"
        }
    }

    var dayCount: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }

    /// 拉取训练记录时的分页大小：周/月拉全部，年只需最新几条。
    var sessionPageSize: Int {
        switch self {
        case .week: return 50
        case .month: return 100
        case .year: return 366
        }
    }

    /// 训练记录列表最多展示条数：周/月展示全部，年只展示最新 6 个。
    var sessionDisplayLimit: Int? {
        switch self {
        case .week, .month: return nil
        case .year: return 6
        }
    }

    /// 时间切换对应的日历单位。
    var calendarComponent: Calendar.Component {
        switch self {
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
}

/// 时间切换后每个周期的起止区间与展示信息。
struct FitnessStatsPeriod {
    let range: FitnessStrengthVolumeRange
    let offset: Int          // 0 = 当前周期，负数为过去
    let interval: DateInterval

    private static let apiFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func current(_ range: FitnessStrengthVolumeRange, offset: Int, calendar: Calendar = .current) -> FitnessStatsPeriod {
        let base = calendar.date(byAdding: range.calendarComponent, value: offset, to: Date()) ?? Date()
        let interval = calendar.dateInterval(of: range.calendarComponent, for: base)
            ?? DateInterval(start: calendar.startOfDay(for: base), duration: 86_400)
        return FitnessStatsPeriod(range: range, offset: offset, interval: interval)
    }

    var startDay: Date { interval.start }

    /// 周期内天数（月 28-31、年 365/366、周 7）。
    var dayCount: Int {
        let days = Calendar.current.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        return max(days, 1)
    }

    var startDateString: String { Self.apiFormatter.string(from: interval.start) }

    /// endDate 用闭区间的最后一天（interval.end 为下一周期起点，需回退一天）。
    var endDateString: String {
        let last = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return Self.apiFormatter.string(from: last)
    }

    var canGoForward: Bool { offset < 0 }

    /// 顶部时间切换显示的标签。
    var label: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        switch range {
        case .week:
            formatter.dateFormat = "M月d日"
            let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(formatter.string(from: interval.start)) - \(formatter.string(from: last))"
        case .month:
            formatter.dateFormat = "yyyy年M月"
            return formatter.string(from: interval.start)
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: interval.start)
        }
    }
}
