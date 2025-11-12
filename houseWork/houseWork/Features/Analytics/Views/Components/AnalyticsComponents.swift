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
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(performance.weekOverWeekDelta >= 0 ? "+" : "")\(performance.weekOverWeekDelta) WoW")
                    .font(.caption2)
                    .foregroundStyle(performance.weekOverWeekDelta >= 0 ? .green : .red)
                Text("\(performance.streakDays)d streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct TrendBarView: View {
    let trend: CompletionTrend
    let maxValue: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(trend.periodLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(trend.completedTasks) tasks")
                    .font(.caption)
            }
            GeometryReader { proxy in
                let ratio = maxValue > 0 ? CGFloat(trend.completedTasks) / CGFloat(maxValue) : 0
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.25))
                    .frame(width: proxy.size.width, height: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor)
                            .frame(width: proxy.size.width * ratio, height: 10),
                        alignment: .leading
                    )
            }
            .frame(height: 12)
        }
    }
}

struct CategoryShareRow: View {
    let share: CategoryShare
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "square.fill")
                        .foregroundStyle(share.color)
                    Text(share.label)
                        .font(.subheadline)
                }
                Spacer()
                Text("\(Int(share.percentage * 100))%")
                    .font(.caption)
            }
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(share.color.opacity(0.2))
                    .frame(width: proxy.size.width, height: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(share.color)
                            .frame(width: proxy.size.width * CGFloat(share.percentage), height: 10),
                        alignment: .leading
                    )
            }
            .frame(height: 12)
        }
    }
}
