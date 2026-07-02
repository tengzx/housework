import SwiftUI
import Combine
import UIKit
import AudioToolbox


// MARK: - ViewModel

@MainActor
final class FitnessTemplateListViewModel: ObservableObject {
    @Published private(set) var templates: [FitnessTemplateSummary] = []
    @Published private(set) var strengthVolume: FitnessStrengthVolumeResponse?
    @Published private(set) var sessionsInRange: [FitnessSessionSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isStatsLoading = false
    @Published private(set) var isSessionsLoading = false
    @Published var selectedStrengthRange: FitnessStrengthVolumeRange = .month
    @Published private(set) var periodOffset = 0

    /// 当前选中的时间周期（含起止区间、标签、能否前进）。
    var period: FitnessStatsPeriod {
        FitnessStatsPeriod.current(selectedStrengthRange, offset: periodOffset)
    }

    /// 训练记录列表：周/月展示全部，年只展示最新 6 个。
    var displaySessions: [FitnessSessionSummary] {
        guard let limit = selectedStrengthRange.sessionDisplayLimit else { return sessionsInRange }
        return Array(sessionsInRange.prefix(limit))
    }

    /// 每个训练日的总训练量，用于打卡热力图着色。
    var checkinVolumeByDay: [Date: Double] {
        let calendar = Calendar.current
        var map: [Date: Double] = [:]
        for session in sessionsInRange {
            let day = calendar.startOfDay(for: session.startedAt)
            map[day, default: 0] += session.totalVolumeKg
        }
        return map
    }
    @Published var errorMessage: String?
    @Published var statsErrorMessage: String?
    @Published var sessionsErrorMessage: String?

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            templates = try await FitnessAPIClient.templates()
        } catch {
            errorMessage = "加载失败，请检查网络"
        }
    }

    func loadAll() async {
        await load()
        await loadStrengthVolume()
        await loadRecentSessions()
    }

    func loadStrengthVolume() async {
        guard !isStatsLoading else { return }
        isStatsLoading = true
        statsErrorMessage = nil
        defer { isStatsLoading = false }
        do {
            let period = self.period
            strengthVolume = try await FitnessAPIClient.strengthVolume(
                range: selectedStrengthRange.rawValue,
                startDate: period.startDateString,
                endDate: period.endDateString
            )
        } catch {
            statsErrorMessage = "统计分析加载失败"
        }
    }

    func loadRecentSessions() async {
        guard !isSessionsLoading else { return }
        isSessionsLoading = true
        sessionsErrorMessage = nil
        defer { isSessionsLoading = false }
        do {
            let period = self.period
            let page = try await FitnessAPIClient.workoutSessions(
                status: "completed",
                startDate: period.startDateString,
                endDate: period.endDateString,
                page: 1,
                pageSize: selectedStrengthRange.sessionPageSize
            )
            sessionsInRange = page.items
        } catch {
            sessionsErrorMessage = "训练记录加载失败"
        }
    }

    func selectStrengthRange(_ range: FitnessStrengthVolumeRange) {
        guard selectedStrengthRange != range else { return }
        selectedStrengthRange = range
        periodOffset = 0
    }

    /// 切到上一个周期。
    func goToPreviousPeriod() {
        periodOffset -= 1
    }

    /// 切到下一个周期（不能越过当前周期）。
    func goToNextPeriod() {
        guard periodOffset < 0 else { return }
        periodOffset += 1
    }

    func update(id: Int, name: String, trainingTheme: String?) async throws {
        try await FitnessAPIClient.updateTemplate(id: id, name: name, trainingTheme: trainingTheme, description: nil)
        await load()
    }

    func delete(id: Int) async {
        do {
            try await FitnessAPIClient.deleteTemplate(id: id)
            templates.removeAll { $0.id == id }
        } catch {
            errorMessage = "删除失败"
        }
    }
}

// MARK: - List View

struct FitnessTemplateListView: View {
    @StateObject private var vm = FitnessTemplateListViewModel()
    @State private var navigateToDetail: FitnessTemplateDetailPayload?
    @State private var navigateToEditor: FitnessTemplateEditorPayload?
    @State private var navigateToSession: FitnessWorkoutSessionPayload?
    @State private var selectedStatsSession: FitnessSessionSummary?
    @State private var templateToDelete: FitnessTemplateSummary?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "F3F2F7"), Color(hex: "EEEDF4")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        HStack(alignment: .center) {
                            Text("体能训练模板")
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                            Spacer()
                            Button { Haptics.tap(); startCreate() } label: {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 38, height: 38)
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Color(hex: "1C1C1E"))
                                    )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 14)

                        if vm.isLoading && vm.templates.isEmpty {
                            ProgressView().padding(40)
                        } else if vm.templates.isEmpty {
                            emptyState.padding(.top, 16)
                        } else {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 12) {
                                ForEach(vm.templates) { tpl in
                                    TemplateGridCard(template: tpl, onDelete: {
                                        Haptics.tap()
                                        templateToDelete = tpl
                                    })
                                        .onTapGesture {
                                            Haptics.tap()
                                            navigateToDetail = FitnessTemplateDetailPayload(
                                                id: tpl.id,
                                                name: tpl.name,
                                                exerciseCount: tpl.exerciseCount,
                                                setCount: tpl.setCount
                                            )
                                        }
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        if !vm.templates.isEmpty {
                            StrengthVolumeAnalysisCard(
                                selectedRange: vm.selectedStrengthRange,
                                period: vm.period,
                                response: vm.strengthVolume,
                                sessions: vm.displaySessions,
                                checkinVolumeByDay: vm.checkinVolumeByDay,
                                isLoading: vm.isStatsLoading,
                                isSessionsLoading: vm.isSessionsLoading,
                                errorMessage: vm.statsErrorMessage,
                                sessionsErrorMessage: vm.sessionsErrorMessage,
                                onSelectRange: { range in
                                    vm.selectStrengthRange(range)
                                    Task {
                                        await vm.loadStrengthVolume()
                                        await vm.loadRecentSessions()
                                    }
                                },
                                onPreviousPeriod: {
                                    vm.goToPreviousPeriod()
                                    Task {
                                        await vm.loadStrengthVolume()
                                        await vm.loadRecentSessions()
                                    }
                                },
                                onNextPeriod: {
                                    vm.goToNextPeriod()
                                    Task {
                                        await vm.loadStrengthVolume()
                                        await vm.loadRecentSessions()
                                    }
                                },
                                onRetry: {
                                    Task { await vm.loadStrengthVolume() }
                                },
                                onRetrySessions: {
                                    Task { await vm.loadRecentSessions() }
                                },
                                onSelectSession: { session in
                                    selectedStatsSession = session
                                }
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 24)

                            Divider()
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                                .padding(.bottom, 16)

                            Button { Haptics.tap(); startCreate() } label: {
                                Text("编辑健身")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color(hex: "1C1C1E"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color(hex: "C9C9CF"), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                    )
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
                .refreshable { await vm.loadAll() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $navigateToDetail) { payload in
                FitnessTemplateDetailView(payload: payload, onEdit: { editorPayload in
                    navigateToEditor = editorPayload
                }, onStart: { sessionPayload in
                    navigateToSession = sessionPayload
                })
            }
            .navigationDestination(item: $navigateToEditor) { payload in
                FitnessTemplateEditorView(
                    payload: payload,
                    onSaved: { await vm.load() },
                    onDeleted: {
                        await vm.load()
                        navigateToEditor = nil
                        navigateToDetail = nil
                    }
                )
            }
            .navigationDestination(item: $navigateToSession) { payload in
                FitnessActiveSessionView(payload: payload) { await vm.load() }
            }
        }
        .sheet(item: $selectedStatsSession) { session in
            FitnessSessionStatsDetailSheet(session: session)
        }
        .alert("错误", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("好") { Haptics.tap(); vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .alert(
            "删除「\(templateToDelete?.name ?? "")」？",
            isPresented: Binding(
                get: { templateToDelete != nil },
                set: { if !$0 { templateToDelete = nil } }
            )
        ) {
            Button("取消", role: .cancel) { Haptics.tap(); templateToDelete = nil }
            Button("删除", role: .destructive) {
                Haptics.tap()
                if let tpl = templateToDelete {
                    Task { await vm.delete(id: tpl.id) }
                }
                templateToDelete = nil
            }
        } message: {
            Text("此操作不可撤销，模板将被归档。")
        }
        .task { await vm.loadAll() }
    }

    // MARK: Empty state

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(hex: "F6F6F8"))
            .frame(height: 200)
            .overlay(
                VStack(spacing: 12) {
                    Text("未添加任何模板")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                    Text("轻点"+"开始创建训练模板")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "7C7C82"))
                    Button { Haptics.tap(); startCreate() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                            Text("新建模板").font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26).padding(.vertical, 13)
                        .background(Color(hex: "1C1C1E"), in: Capsule())
                    }
                }
            )
            .padding(.horizontal, 16)
    }

    // MARK: Helpers

    /// 跳转到编辑界面开始新建，模板要等到点击“保存”时才真正创建；名称可在编辑界面修改。
    private func startCreate() {
        navigateToEditor = FitnessTemplateEditorPayload(id: nil, name: "新模板")
    }
}

// MARK: - Template Grid Card

private struct TemplateGridCard: View {
    let template: FitnessTemplateSummary
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(template.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 28)

            Text("\(template.exerciseCount) 种锻炼, \(template.setCount) 组")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "9A9AA0"))
                .padding(.top, 4)
                .lineLimit(1)

            Spacer(minLength: 14)

            HStack(alignment: .bottom, spacing: 5) {
                HStack(spacing: 3) {
                    ForEach(volumeDigits, id: \.offset) { item in
                        Text(item.element)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                            .frame(minWidth: 21, minHeight: 30)
                            .padding(.horizontal, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color(hex: "ECECEF"), lineWidth: 1)
                            )
                    }
                }
                Text("kg")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "9A9AA0"))
                    .padding(.bottom, 3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        .overlay(alignment: .topTrailing) {
            Menu {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除模板", systemImage: "trash")
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "9A9AA0"))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .padding(.top, 6)
            .padding(.trailing, 6)
        }
    }

    private var volumeDigits: [(offset: Int, element: String)] {
        let str = template.estimatedVolumeKg > 0 ? String(Int(template.estimatedVolumeKg)) : "0"
        return Array(str.enumerated()).map { (offset: $0.offset, element: String($0.element)) }
    }
}
