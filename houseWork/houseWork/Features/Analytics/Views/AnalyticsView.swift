//
//  AnalyticsView.swift
//  houseWork
//
//  Household performance dashboard with leaderboards and trends.
//

import SwiftUI

struct AnalyticsView: View {
    @EnvironmentObject private var taskStore: TaskBoardStore
    @StateObject private var viewModel = AnalyticsViewModel()
    @State private var useCustomRange = false
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var customEnd = Date()
    
    var body: some View {
        navigationContainer {
            ScrollView {
                VStack(spacing: 20) {
                    rangePicker
                    customRangeSection
                    metricsSection
                    leaderboardSection
                }
                .padding()
            }
            .refreshable {
                await taskStore.refresh()
                await MainActor.run {
                    refreshAnalytics()
                }
            }
            .background(Color(.systemGroupedBackground))
            .onAppear { refreshAnalytics() }
            .onChange(of: taskStore.tasks) { _ in refreshAnalytics() }
            .onChange(of: viewModel.selectedRange) { _ in
                guard !useCustomRange else { return }
                refreshAnalytics()
            }
            .onChange(of: useCustomRange) { _ in refreshAnalytics() }
            .onChange(of: customStart) { newValue in
                if newValue > customEnd { customEnd = newValue }
                if useCustomRange { refreshAnalytics() }
            }
            .onChange(of: customEnd) { newValue in
                if newValue < customStart { customStart = newValue }
                if useCustomRange { refreshAnalytics() }
            }
        }
    }
    
    // MARK: - Sections
    
    private var rangePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AnalyticsRange.allCases) { range in
                    RangeChip(
                        label: LocalizedStringKey(range.labelKey),
                        isSelected: viewModel.selectedRange == range && !useCustomRange
                    ) {
                        useCustomRange = false
                        viewModel.selectedRange = range
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var customRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $useCustomRange) {
                Text(LocalizedStringKey("analytics.customRange.title"))
                    .font(.headline)
            }
            .toggleStyle(SwitchToggleStyle())
            
            if useCustomRange {
                VStack(alignment: .leading, spacing: 12) {
                    DatePicker(LocalizedStringKey("analytics.date.start"), selection: $customStart, displayedComponents: .date)
                    DatePicker(LocalizedStringKey("analytics.date.end"), selection: $customEnd, displayedComponents: .date)
                }
                .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
    }
    
    private var metricsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                MetricCardView(
                    titleKey: "analytics.metric.totalPoints",
                    value: "\(viewModel.totalPoints)",
                    subtitle: metricsSubtitle,
                    icon: "star.fill",
                    tint: .yellow
                )
                MetricCardView(
                    titleKey: "analytics.metric.avgTasks",
                    value: "\(viewModel.averageTasksPerMember)",
                    subtitle: String(localized: "analytics.metric.avgTasks.subtitle"),
                    icon: "chart.bar.fill",
                    tint: .blue
                )
                MetricCardView(
                    titleKey: "analytics.metric.topStreak",
                    value: "\(viewModel.householdStreak)d",
                    subtitle: String(localized: "analytics.metric.topStreak.subtitle"),
                    icon: "flame.fill",
                    tint: .orange
                )
            }
            .padding(.horizontal, 4)
        }
    }
    
    private var leaderboardSection: some View {
        SectionCard(title: LocalizedStringKey("analytics.section.leaderboard"), icon: "trophy.fill") {
            ForEach(Array(viewModel.memberStats.enumerated()), id: \.element.id) { index, stat in
                LeaderboardRow(performance: stat, rank: index + 1)
                if index != viewModel.memberStats.count - 1 {
                    Divider()
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func refreshAnalytics() {
        viewModel.refresh(using: taskStore.tasks, customRange: activeCustomRange)
    }
    
    private var activeCustomRange: DateInterval? {
        guard useCustomRange else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: customStart)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEnd)) ?? customEnd
        return DateInterval(start: start, end: end)
    }
    
    private var metricsSubtitle: String {
        if useCustomRange, let interval = activeCustomRange {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "\(formatter.string(from: interval.start)) – \(formatter.string(from: interval.end.addingTimeInterval(-1)))"
        }
        return String(localized: .init(viewModel.selectedRange.metricSubtitleKey))
    }
}

private struct SectionCard<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    @ViewBuilder var content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}

private struct RangeChip: View {
    let label: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.16) : Color(.secondarySystemGroupedBackground))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    navigationContainer {
        AnalyticsView()
            .environmentObject(TaskBoardStore(previewTasks: TaskItem.fixtures()))
    }
}
