//
//  AnalyticsModels.swift
//  houseWork
//
//  Models powering the Analytics dashboard.
//

import SwiftUI

struct MemberPerformance: Identifiable {
    let id = UUID()
    var member: HouseholdMember
    var tasksCompleted: Int
    var pointsEarned: Int
    var streakDays: Int
    var weekOverWeekDelta: Int
}

struct CompletionTrend: Identifiable {
    let id = UUID()
    var periodLabel: String
    var completedTasks: Int
}

struct CategoryShare: Identifiable {
    let id = UUID()
    var label: String
    var percentage: Double
    var color: Color
}
