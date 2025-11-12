//
//  AnalyticsViewModel.swift
//  houseWork
//
//  Supplies derived metrics for the Analytics dashboard.
//

import Foundation
import SwiftUI
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
    @Published var memberStats: [MemberPerformance]
    @Published var trend: [CompletionTrend]
    @Published var categoryShare: [CategoryShare]
    @Published var selectedRange: AnalyticsRange
    
    init(selectedRange: AnalyticsRange = .weekly) {
        self.selectedRange = selectedRange
        let dataset = AnalyticsViewModel.dataset(for: selectedRange)
        self.memberStats = dataset.memberStats
        self.trend = dataset.trend
        self.categoryShare = dataset.categoryShare
    }
    
    func refreshData() {
        let dataset = AnalyticsViewModel.dataset(for: selectedRange)
        memberStats = dataset.memberStats
        trend = dataset.trend
        categoryShare = dataset.categoryShare
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
        memberStats.sorted { $0.pointsEarned > $1.pointsEarned }.first
    }
}

// MARK: - Sample Data

private struct AnalyticsDataset {
    let memberStats: [MemberPerformance]
    let trend: [CompletionTrend]
    let categoryShare: [CategoryShare]
}

extension AnalyticsViewModel {
    private static func dataset(for range: AnalyticsRange) -> AnalyticsDataset {
        let baseStats = sampleMemberStats()
        let shares = baseCategoryShare()
        switch range {
        case .daily:
            return AnalyticsDataset(
                memberStats: scale(stats: baseStats, factor: 0.2, streakMultiplier: 1.0, streakCap: 3),
                trend: dailyTrend(),
                categoryShare: shares
            )
        case .weekly:
            return AnalyticsDataset(
                memberStats: baseStats,
                trend: weeklyTrend(),
                categoryShare: shares
            )
        case .monthly:
            return AnalyticsDataset(
                memberStats: scale(stats: baseStats, factor: 4.0, streakMultiplier: 2.5, streakCap: 21),
                trend: monthlyTrend(),
                categoryShare: shares
            )
        case .quarterly:
            return AnalyticsDataset(
                memberStats: scale(stats: baseStats, factor: 12.0, streakMultiplier: 6.0, streakCap: 45),
                trend: quarterlyTrend(),
                categoryShare: shares
            )
        case .yearly:
            return AnalyticsDataset(
                memberStats: scale(stats: baseStats, factor: 48.0, streakMultiplier: 10.0, streakCap: 160),
                trend: yearlyTrend(),
                categoryShare: shares
            )
        }
    }
    
    private static func scale(stats: [MemberPerformance], factor: Double, streakMultiplier: Double, streakCap: Int) -> [MemberPerformance] {
        stats.map { stat in
            MemberPerformance(
                member: stat.member,
                tasksCompleted: max(1, Int((Double(stat.tasksCompleted) * factor).rounded())),
                pointsEarned: max(1, Int((Double(stat.pointsEarned) * factor).rounded())),
                streakDays: min(max(1, Int((Double(stat.streakDays) * streakMultiplier).rounded())), streakCap),
                weekOverWeekDelta: stat.weekOverWeekDelta
            )
        }
    }
    
    private static func sampleMemberStats() -> [MemberPerformance] {
        let members = HouseholdMember.samples
        return [
            MemberPerformance(member: members[0], tasksCompleted: 18, pointsEarned: 260, streakDays: 5, weekOverWeekDelta: 3),
            MemberPerformance(member: members[1], tasksCompleted: 14, pointsEarned: 220, streakDays: 4, weekOverWeekDelta: -1),
            MemberPerformance(member: members[2], tasksCompleted: 12, pointsEarned: 210, streakDays: 2, weekOverWeekDelta: 2),
            MemberPerformance(member: members[3], tasksCompleted: 9, pointsEarned: 150, streakDays: 1, weekOverWeekDelta: 0),
            MemberPerformance(member: members[4], tasksCompleted: 7, pointsEarned: 120, streakDays: 1, weekOverWeekDelta: 1)
        ]
    }
    
    private static func dailyTrend() -> [CompletionTrend] {
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let values = [5, 6, 4, 7, 8, 6, 5]
        return zip(labels, values).map { CompletionTrend(periodLabel: $0.0, completedTasks: $0.1) }
    }
    
    private static func weeklyTrend() -> [CompletionTrend] {
        [
            CompletionTrend(periodLabel: "Week 40", completedTasks: 26),
            CompletionTrend(periodLabel: "Week 41", completedTasks: 31),
            CompletionTrend(periodLabel: "Week 42", completedTasks: 34),
            CompletionTrend(periodLabel: "Week 43", completedTasks: 28),
            CompletionTrend(periodLabel: "Week 44", completedTasks: 36)
        ]
    }
    
    private static func monthlyTrend() -> [CompletionTrend] {
        let labels = ["May", "Jun", "Jul", "Aug", "Sep", "Oct"]
        let values = [96, 104, 118, 110, 124, 132]
        return zip(labels, values).map { CompletionTrend(periodLabel: $0.0, completedTasks: $0.1) }
    }
    
    private static func quarterlyTrend() -> [CompletionTrend] {
        [
            CompletionTrend(periodLabel: "Q1 2025", completedTasks: 310),
            CompletionTrend(periodLabel: "Q2 2025", completedTasks: 340),
            CompletionTrend(periodLabel: "Q3 2025", completedTasks: 365),
            CompletionTrend(periodLabel: "Q4 2025", completedTasks: 330)
        ]
    }
    
    private static func yearlyTrend() -> [CompletionTrend] {
        [
            CompletionTrend(periodLabel: "2021", completedTasks: 1120),
            CompletionTrend(periodLabel: "2022", completedTasks: 1280),
            CompletionTrend(periodLabel: "2023", completedTasks: 1420),
            CompletionTrend(periodLabel: "2024", completedTasks: 1510),
            CompletionTrend(periodLabel: "2025", completedTasks: 980)
        ]
    }
    
    private static func baseCategoryShare() -> [CategoryShare] {
        [
            CategoryShare(label: "Kitchen", percentage: 0.28, color: .orange),
            CategoryShare(label: "Laundry", percentage: 0.18, color: .blue),
            CategoryShare(label: "Cleaning", percentage: 0.32, color: .green),
            CategoryShare(label: "Errands", percentage: 0.14, color: .purple),
            CategoryShare(label: "Yard", percentage: 0.08, color: .pink)
        ]
    }
}
