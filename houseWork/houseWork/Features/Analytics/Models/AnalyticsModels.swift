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
    var minutesLogged: Int
    var streakDays: Int
    var weekOverWeekDelta: Int
}
