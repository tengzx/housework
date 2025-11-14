//
//  AnalyticsViewModel.swift
//  houseWork
//
//  Aggregates live TaskBoard data into analytics-friendly structures.
//

import Foundation
import Combine

enum AnalyticsRange: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case quarterly
    case yearly
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .yearly: "Yearly"
        }
    }
    
    var metricSubtitle: String {
        switch self {
        case .daily: "Today"
        case .weekly: "This week"
        case .monthly: "This month"
        case .quarterly: "This quarter"
        case .yearly: "This year"
        }
    }
}

final class AnalyticsViewModel: ObservableObject {
    @Published var memberStats: [MemberPerformance] = []
    @Published var selectedRange: AnalyticsRange = .weekly
    
    func refresh(using tasks: [TaskItem], customRange: DateInterval? = nil) {
        let buckets: [AnalyticsBucket]
        if let customRange {
            buckets = AnalyticsBucket.customBucket(for: customRange)
        } else {
            buckets = AnalyticsBucket.makeBuckets(for: selectedRange)
        }
        guard !buckets.isEmpty else {
            memberStats = []
            return
        }
        
        let windowStart = buckets.first!.interval.start
        let windowEnd = buckets.last!.interval.end
        let completedTasks = tasks.filter { task in
            guard task.status == .completed else { return false }
            let finishDate = task.completedAt ?? task.dueDate
            return finishDate >= windowStart && finishDate <= windowEnd
        }
        
        memberStats = buildMemberStats(from: completedTasks, buckets: buckets)
    }
    
    var totalPoints: Int {
        memberStats.reduce(0) { $0 + $1.pointsEarned }
    }
    
    var averageTasksPerMember: Int {
        guard !memberStats.isEmpty else { return 0 }
        let total = memberStats.reduce(0) { $0 + $1.tasksCompleted }
        return Int(round(Double(total) / Double(memberStats.count)))
    }
    
    var householdStreak: Int {
        memberStats.map(\.streakDays).max() ?? 0
    }
    
    var topPerformer: MemberPerformance? {
        memberStats.max(by: { $0.pointsEarned < $1.pointsEarned })
    }
    
    // MARK: - Builders
    
    private func buildMemberStats(from tasks: [TaskItem], buckets: [AnalyticsBucket]) -> [MemberPerformance] {
        var accumulators: [MemberAccumulator] = []
        for task in tasks {
            let completionDate = task.completedAt ?? task.dueDate
            let bucketIndex = bucketIndex(for: completionDate, buckets: buckets)
            for member in task.assignedMembers {
                let matchIndex = accumulators.firstIndex(where: { $0.member.matches(member) })
                var entry = matchIndex.map { accumulators[$0] } ?? MemberAccumulator(member: member, bucketCount: buckets.count)
                if let bucketIndex {
                    entry.bucketCounts[bucketIndex] += 1
                    if bucketIndex == buckets.count - 1 {
                        entry.tasksCompleted += 1
                        entry.pointsEarned += task.score
                        entry.minutesLogged += task.estimatedMinutes
                        entry.completionDates.append(completionDate)
                    }
                }
                if let matchIndex {
                    accumulators[matchIndex] = entry
                } else {
                    accumulators.append(entry)
                }
            }
        }
        
        return accumulators
            .map { accumulator in
                let streak = streakDays(for: accumulator.completionDates)
                let delta: Int
                if accumulator.bucketCounts.count >= 2 {
                    delta = accumulator.bucketCounts.last! - accumulator.bucketCounts[accumulator.bucketCounts.count - 2]
                } else {
                    delta = accumulator.bucketCounts.last ?? 0
                }
                return MemberPerformance(
                    member: accumulator.member,
                    tasksCompleted: accumulator.tasksCompleted,
                    pointsEarned: accumulator.pointsEarned,
                    minutesLogged: accumulator.minutesLogged,
                    streakDays: streak,
                    weekOverWeekDelta: delta
                )
            }
            .sorted { $0.pointsEarned > $1.pointsEarned }
    }
    
    // MARK: - Helpers
    
    private func bucketIndex(for date: Date, buckets: [AnalyticsBucket]) -> Int? {
        for (idx, bucket) in buckets.enumerated() where bucket.interval.contains(date) {
            return idx
        }
        return nil
    }
    
    private func streakDays(for dates: [Date]) -> Int {
        guard !dates.isEmpty else { return 0 }
        let calendar = Calendar.current
        var uniqueDays = Set(dates.map { calendar.startOfDay(for: $0) })
        var streak = 0
        var cursor = calendar.startOfDay(for: Date())
        while uniqueDays.contains(cursor) {
            streak += 1
            uniqueDays.remove(cursor)
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}

// MARK: - Supporting Types

private struct MemberAccumulator {
    let member: HouseholdMember
    var tasksCompleted: Int = 0
    var pointsEarned: Int = 0
    var minutesLogged: Int = 0
    var completionDates: [Date] = []
    var bucketCounts: [Int]
    
    init(member: HouseholdMember, bucketCount: Int) {
        self.member = member
        self.bucketCounts = Array(repeating: 0, count: bucketCount)
    }
}

private struct AnalyticsBucket {
    let label: String
    let interval: DateInterval
    
    static func customBucket(for interval: DateInterval) -> [AnalyticsBucket] {
        guard interval.end > interval.start else { return [] }
        return [AnalyticsBucket(label: "Custom", interval: interval)]
    }
    
    static func makeBuckets(for range: AnalyticsRange, reference date: Date = Date()) -> [AnalyticsBucket] {
        let calendar = Calendar.current
        switch range {
        case .daily:
            let startOfToday = calendar.startOfDay(for: date)
            return (0..<7).reversed().map { offset in
                let start = calendar.date(byAdding: .day, value: -offset, to: startOfToday)!
                let end = calendar.date(byAdding: .day, value: 1, to: start)!
                let label = DateFormatter.shortWeekday.string(from: start)
                return AnalyticsBucket(label: label, interval: DateInterval(start: start, end: end))
            }
        case .weekly:
            guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
            return (0..<5).reversed().map { offset in
                let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek.start)!
                let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
                let weekNumber = calendar.component(.weekOfYear, from: start)
                let label = "Week \(weekNumber)"
                return AnalyticsBucket(label: label, interval: DateInterval(start: start, end: end))
            }
        case .monthly:
            guard let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else { return [] }
            return (0..<6).reversed().map { offset in
                let start = calendar.date(byAdding: .month, value: -offset, to: currentMonth)!
                let end = calendar.date(byAdding: .month, value: 1, to: start)!
                let label = DateFormatter.shortMonth.string(from: start)
                return AnalyticsBucket(label: label, interval: DateInterval(start: start, end: end))
            }
        case .quarterly:
            guard let currentQuarterStart = calendar.startOfQuarter(for: date) else { return [] }
            return (0..<4).reversed().map { offset in
                let start = calendar.date(byAdding: .month, value: -offset * 3, to: currentQuarterStart)!
                let end = calendar.date(byAdding: .month, value: 3, to: start)!
                let quarterNumber = calendar.quarterNumber(for: start)
                let year = calendar.component(.year, from: start)
                let label = "Q\(quarterNumber) \(year)"
                return AnalyticsBucket(label: label, interval: DateInterval(start: start, end: end))
            }
        case .yearly:
            guard let currentYear = calendar.date(from: calendar.dateComponents([.year], from: date)) else { return [] }
            return (0..<5).reversed().map { offset in
                let start = calendar.date(byAdding: .year, value: -offset, to: currentYear)!
                let end = calendar.date(byAdding: .year, value: 1, to: start)!
                let label = DateFormatter.year.string(from: start)
                return AnalyticsBucket(label: label, interval: DateInterval(start: start, end: end))
            }
        }
    }
}

private extension Calendar {
    func startOfQuarter(for date: Date) -> Date? {
        let comps = dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return nil }
        let quarter = ((month - 1) / 3) + 1
        let startMonth = (quarter - 1) * 3 + 1
        return self.date(from: DateComponents(year: year, month: startMonth))
    }
    
    func quarterNumber(for date: Date) -> Int {
        let month = component(.month, from: date)
        return ((month - 1) / 3) + 1
    }
}

private extension DateFormatter {
    static let shortWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()
    
    static let shortMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()
    
    static let year: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("yyyy")
        return formatter
    }()
}
