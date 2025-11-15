//
//  AnalyticsComponents.swift
//  houseWork
//
//  Reusable UI components for Analytics dashboard.
//

import SwiftUI

struct MetricCardView: View {
    let titleKey: LocalizedStringKey
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(titleKey, systemImage: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct LeaderboardRow: View {
    let performance: MemberPerformance
    let rank: Int
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline)
                .frame(width: 28)
                .foregroundStyle(rank == 1 ? Color.accentColor : .secondary)
            MemberAvatarView(member: performance.member, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(performance.member.name)
                    .font(.subheadline.bold())
                Text(tasksAndPointsText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(minutesLoggedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(deltaText)
                    .font(.caption2)
                    .foregroundStyle(performance.weekOverWeekDelta >= 0 ? .green : .red)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var tasksAndPointsText: String {
        let template = String(localized: "analytics.leaderboard.tasksAndPoints")
        return String(format: template, performance.tasksCompleted, performance.pointsEarned)
    }
    
    private var minutesLoggedText: String {
        let template = String(localized: "analytics.leaderboard.minutesLogged")
        return String(format: template, performance.minutesLogged)
    }
    
    private var deltaText: String {
        let template = String(localized: "analytics.leaderboard.delta")
        return String(format: template, performance.weekOverWeekDelta)
    }
}
