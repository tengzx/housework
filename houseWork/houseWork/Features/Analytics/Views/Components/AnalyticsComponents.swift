//
//  AnalyticsComponents.swift
//  houseWork
//
//  Reusable UI components for Analytics dashboard.
//

import SwiftUI

struct MetricCardView: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
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
            Text(performance.member.initials)
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(performance.member.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(performance.member.name)
                    .font(.subheadline.bold())
                Text("\(performance.tasksCompleted) tasks · \(performance.pointsEarned) pts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(performance.minutesLogged) min logged")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(performance.weekOverWeekDelta >= 0 ? "+" : "")\(performance.weekOverWeekDelta) WoW")
                    .font(.caption2)
                    .foregroundStyle(performance.weekOverWeekDelta >= 0 ? .green : .red)
            }
        }
        .padding(.vertical, 8)
    }
}
