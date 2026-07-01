import SwiftUI
import Combine
import UIKit
import AudioToolbox

// MARK: - ViewModel

@MainActor
final class FitnessTemplateListViewModel: ObservableObject {
    @Published private(set) var templates: [FitnessTemplateSummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

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
    @State private var showCreateSheet = false
    @State private var isCreating = false
    @State private var pendingCreation: (name: String, theme: String?)?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "EFEFF2").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        headerView
                            .padding(.top, 6)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 18)

                        HStack(alignment: .center) {
                            Text("体能训练模板")
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                            Spacer()
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: "E4E4E9"))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Text("···")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(Color(hex: "5B5B61"))
                                            .offset(y: -3)
                                    )
                                Button { showCreateSheet = true } label: {
                                    Circle()
                                        .fill(Color(hex: "E4E4E9"))
                                        .frame(width: 34, height: 34)
                                        .overlay(
                                            Image(systemName: "plus")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(Color(hex: "5B5B61"))
                                        )
                                }
                                .disabled(isCreating)
                            }
                        }
                        .padding(.horizontal, 20)
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
                                    TemplateGridCard(template: tpl)
                                        .onTapGesture {
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
                            Divider()
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                                .padding(.bottom, 16)

                            Button { showCreateSheet = true } label: {
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
                .refreshable { await vm.load() }
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
        // 新建 sheet
        .sheet(isPresented: $showCreateSheet, onDismiss: {
            if let creation = pendingCreation {
                pendingCreation = nil
                Task { @MainActor in
                    try? await createAndNavigate(name: creation.name, theme: creation.theme)
                }
            }
        }) {
            TemplateInfoSheet(
                title: "新建模板",
                confirmLabel: "创建",
                initialName: "",
                initialTheme: ""
            ) { name, theme in
                pendingCreation = (name: name, theme: theme)
            }
        }
        .alert("错误", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("好") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .task { await vm.load() }
    }

    // MARK: Header

    private var headerView: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("健身")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Text("过去 30 天")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "9A9AA0"))
            }
            HStack {
                Spacer()
                Button { showCreateSheet = true } label: {
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
                .disabled(isCreating)
            }
        }
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
                    Button { showCreateSheet = true } label: {
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

    @MainActor private func createAndNavigate(name: String, theme: String?) async throws {
        isCreating = true
        defer { isCreating = false }
        let resp = try await FitnessAPIClient.createTemplate(name: name, description: nil, trainingTheme: theme?.isEmpty == true ? nil : theme)
        await vm.load()
        navigateToEditor = FitnessTemplateEditorPayload(id: resp.id, name: resp.name)
    }
}

// MARK: - Template Detail View

struct FitnessTemplateDetailPayload: Hashable, Identifiable {
    let id: Int
    let name: String
    let exerciseCount: Int
    let setCount: Int
}

@MainActor
final class FitnessTemplateDetailViewModel: ObservableObject {
    let payload: FitnessTemplateDetailPayload
    @Published private(set) var detail: FitnessTemplateDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var isStarting = false
    @Published var errorMessage: String?
    @Published var startMessage: String?

    init(payload: FitnessTemplateDetailPayload) {
        self.payload = payload
    }

    var title: String { detail?.name ?? payload.name }

    var exerciseCount: Int { detail?.exercises.count ?? payload.exerciseCount }

    var setCount: Int {
        detail?.exercises.reduce(0) { $0 + $1.sets.count } ?? payload.setCount
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            detail = try await FitnessAPIClient.templateDetail(id: payload.id)
        } catch {
            errorMessage = "加载失败，请检查网络"
        }
    }

    func startWorkout() async -> FitnessWorkoutSessionPayload? {
        guard !isStarting else { return nil }
        isStarting = true
        startMessage = nil
        defer { isStarting = false }
        do {
            let response = try await FitnessAPIClient.startSession(templateId: payload.id, name: title)
            return FitnessWorkoutSessionPayload(sessionId: response.sessionId, name: title)
        } catch {
            startMessage = "开始训练失败，请检查网络"
            return nil
        }
    }
}

struct FitnessTemplateDetailView: View {
    let payload: FitnessTemplateDetailPayload
    let onEdit: (FitnessTemplateEditorPayload) -> Void
    let onStart: (FitnessWorkoutSessionPayload) -> Void

    @StateObject private var vm: FitnessTemplateDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        payload: FitnessTemplateDetailPayload,
        onEdit: @escaping (FitnessTemplateEditorPayload) -> Void,
        onStart: @escaping (FitnessWorkoutSessionPayload) -> Void
    ) {
        self.payload = payload
        self.onEdit = onEdit
        self.onStart = onStart
        _vm = StateObject(wrappedValue: FitnessTemplateDetailViewModel(payload: payload))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(vm.title)
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                            .padding(.horizontal, 20)
                            .padding(.top, 26)

                        Text("\(vm.exerciseCount) 种锻炼, \(vm.setCount) 组")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(hex: "8E8E93"))
                            .padding(.horizontal, 20)
                            .padding(.top, 6)

                        if vm.isLoading && vm.detail == nil {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 48)
                        } else if let detail = vm.detail {
                            VStack(spacing: 12) {
                                ForEach(detail.exercises) { exercise in
                                    TemplateDetailExerciseRow(exercise: exercise)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 28)
                        } else if let errorMessage = vm.errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color(hex: "F05B5B"))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 48)
                        }

                        devicePickerRow
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }
                    .padding(.bottom, 150)
                }
            }

            bottomActions
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.load() }
        .alert("提示", isPresented: Binding(
            get: { vm.startMessage != nil },
            set: { if !$0 { vm.startMessage = nil } }
        )) {
            Button("好") { vm.startMessage = nil }
        } message: {
            Text(vm.startMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Circle()
                    .fill(Color(hex: "F1F1F4"))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                    )
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var devicePickerRow: some View {
        HStack {
            Text("设备")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: "9A9AA0"))
            Spacer()
            HStack(spacing: 8) {
                Text("仅 iPhone")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "8E8E93"))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: "EEEEF1"), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 16, y: 8)
    }

    private var bottomActions: some View {
        HStack(spacing: 12) {
            Button {
                onEdit(FitnessTemplateEditorPayload(id: payload.id, name: vm.title))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 17, weight: .semibold))
                    Text("编辑")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(Color(hex: "1C1C1E"))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Color(hex: "F1F1F4"), in: Capsule())
            }

            Button {
                Task {
                    if let sessionPayload = await vm.startWorkout() {
                        onStart(sessionPayload)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if vm.isStarting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                        Text("开始")
                            .font(.system(size: 18, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Color(hex: "1C1C1E"), in: Capsule())
            }
            .disabled(vm.setCount == 0 || vm.isStarting)
            .opacity(vm.setCount == 0 ? 0.45 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
        .padding(.top, 24)
        .background(
            LinearGradient(
                colors: [.white, .white.opacity(0.96), .white.opacity(0)],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea()
        )
    }
}

private struct TemplateDetailExerciseRow: View {
    let exercise: TemplateDetailExercise

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "F6F6F8"))
                .frame(width: 58, height: 58)
                .overlay(BarbellIcon())

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .lineLimit(1)
                Text("\(exercise.categoryName ?? "——") · \(exercise.sets.count) 组")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "8E8E93"))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 76)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: "EEEEF1"), lineWidth: 1)
        )
    }
}

// MARK: - Active Session View

/// Picks the set the workout should advance to next.
///
/// While the exercise of the most-recently-completed set still has an available
/// set, keep advancing within that same exercise (finish the current exercise
/// before moving on). Only once that exercise is fully done do we fall back to
/// the first available set overall — which surfaces any earlier exercise the
/// user skipped over.
private func fitnessNextTargetContext(
    in contexts: [(exercise: FitnessSessionExercise, set: FitnessSessionSet)]
) -> (exercise: FitnessSessionExercise, set: FitnessSessionSet)? {
    func isAvailable(_ context: (exercise: FitnessSessionExercise, set: FitnessSessionSet)) -> Bool {
        !context.set.isCompleted && context.set.timerStatus != "running"
    }
    let lastCompleted = contexts
        .filter { $0.set.isCompleted }
        .max { ($0.set.completedAt ?? .distantPast) < ($1.set.completedAt ?? .distantPast) }
    if let lastCompleted,
       let sameExerciseNext = contexts.first(where: {
           $0.exercise.sessionExerciseId == lastCompleted.exercise.sessionExerciseId && isAvailable($0)
       }) {
        return sameExerciseNext
    }
    return contexts.first(where: isAvailable)
}

struct FitnessWorkoutSessionPayload: Hashable, Identifiable {
    let sessionId: Int
    let name: String

    var id: Int { sessionId }
}

@MainActor
final class FitnessActiveSessionViewModel: ObservableObject {
    let payload: FitnessWorkoutSessionPayload
    @Published private(set) var detail: FitnessSessionDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var isCompleting = false
    @Published private(set) var isPausing = false
    @Published private(set) var isDiscarding = false
    @Published private(set) var isAddingExercise = false
    @Published private(set) var isSessionPaused = false
    @Published private(set) var savingSetIds: Set<Int> = []
    @Published private(set) var updatingSetIds: Set<Int> = []
    @Published private(set) var savingExerciseIds: Set<Int> = []
    @Published var errorMessage: String?

    private var sessionPausedAt: Date?
    private var accumulatedSessionPauseSeconds = 0

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(payload: FitnessWorkoutSessionPayload) {
        self.payload = payload
    }

    var title: String { detail?.name ?? payload.name }
    var startedAt: Date { detail?.startedAt ?? .now }
    var hasRunningSet: Bool {
        guard let detail else { return false }
        return orderedSetContexts(from: detail).contains { $0.set.timerStatus == "running" }
    }

    var shouldShowSessionControls: Bool {
        !hasRunningSet
    }

    var incompleteSetCount: Int {
        guard let exercises = detail?.exercises else { return 0 }
        return exercises.reduce(0) { total, ex in
            total + ex.sets.filter { !$0.isCompleted }.count
        }
    }

    func elapsedSeconds(at now: Date) -> Int {
        let end = isSessionPaused ? (sessionPausedAt ?? now) : now
        return max(0, Int(end.timeIntervalSince(startedAt)) - accumulatedSessionPauseSeconds)
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            detail = try await FitnessAPIClient.sessionDetail(id: payload.sessionId)
        } catch {
            errorMessage = "训练详情加载失败"
        }
    }

    func toggleSetCompletion(exerciseId: Int, setId: Int) async {
        guard let detail, !savingSetIds.contains(setId) else { return }
        let contexts = orderedSetContexts(from: detail)
        guard let target = contexts.first(where: { $0.exercise.sessionExerciseId == exerciseId && $0.set.sessionSetId == setId }) else { return }
        let shouldStartSet = !target.set.isCompleted && target.set.timerStatus != "running"
        savingSetIds.insert(setId)
        errorMessage = nil
        defer { savingSetIds.remove(setId) }
        do {
            let request = makeStructureRequest(from: detail) { exercise, set in
                if set.sessionSetId != setId {
                    if shouldStartSet, set.timerStatus == "running" {
                        let elapsed = set.timerStartedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
                        return sessionSetRequest(
                            from: set,
                            exercise: exercise,
                            timerStatusOverride: "idle",
                            clearTimerStartedAt: true,
                            timerAccumulatedSecondsOverride: (set.timerAccumulatedSeconds ?? 0) + elapsed
                        )
                    }
                    if shouldStartSet, set.timerStatus == "paused" {
                        return sessionSetRequest(
                            from: set,
                            exercise: exercise,
                            timerStatusOverride: "idle",
                            clearTimerStartedAt: true
                        )
                    }
                    return sessionSetRequest(from: set, exercise: exercise)
                }
                if set.isCompleted {
                    return sessionSetRequest(
                        from: set,
                        exercise: exercise,
                        isCompletedOverride: false,
                        completedAtOverride: nil,
                        clearCompletedAt: true,
                        timerStatusOverride: "idle",
                        clearTimerStartedAt: true
                    )
                }
                if set.timerStatus == "running" {
                    let elapsed = set.timerStartedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
                    let totalSeconds = (set.timerAccumulatedSeconds ?? 0) + elapsed
                    return sessionSetRequest(
                        from: set,
                        exercise: exercise,
                        isCompletedOverride: true,
                        completedAtOverride: Self.isoFormatter.string(from: .now),
                        timerStatusOverride: "idle",
                        timerAccumulatedSecondsOverride: totalSeconds,
                        actualDurationSecondsOverride: exercise.isTimeBased ? totalSeconds : nil
                    )
                }
                return sessionSetRequest(
                    from: set,
                    exercise: exercise,
                    isCompletedOverride: false,
                    completedAtOverride: nil,
                    timerStatusOverride: "running",
                    timerStartedAtOverride: Self.isoFormatter.string(from: .now)
                )
            }
            _ = try await FitnessAPIClient.saveSessionStructure(id: payload.sessionId, request: request)
            if shouldStartSet {
                if let pausedAt = sessionPausedAt {
                    accumulatedSessionPauseSeconds += max(0, Int(Date().timeIntervalSince(pausedAt)))
                }
                sessionPausedAt = nil
                isSessionPaused = false
            }
            await load()
        } catch {
            errorMessage = "保存组状态失败，请检查网络"
        }
    }

    func addSet(to exerciseId: Int) async {
        guard let detail, !savingExerciseIds.contains(exerciseId) else { return }
        savingExerciseIds.insert(exerciseId)
        errorMessage = nil
        defer { savingExerciseIds.remove(exerciseId) }
        do {
            let request = makeStructureRequest(from: detail) { exercise, set in
                sessionSetRequest(from: set, exercise: exercise)
            } appendedSetForExerciseId: { exercise in
                guard exercise.sessionExerciseId == exerciseId else { return nil }
                let last = exercise.sets.last
                return FitnessSessionSetRequest(
                    sessionSetId: nil,
                    setOrder: exercise.sets.count + 1,
                    setType: last?.setType ?? "normal",
                    plannedWeightKg: last?.plannedWeightKg ?? (exercise.trackingType == "weight_reps" ? 10 : nil),
                    plannedReps: last?.plannedReps ?? (exercise.isTimeBased ? nil : 12),
                    plannedDurationSeconds: last?.plannedDurationSeconds ?? (exercise.isTimeBased ? 30 : nil),
                    plannedDistanceMeters: last?.plannedDistanceMeters ?? (ExerciseTrackingDisplay.isDistanceBased(exercise.trackingType) ? 100 : nil),
                    actualWeightKg: nil,
                    actualReps: nil,
                    actualDurationSeconds: nil,
                    actualDistanceMeters: nil,
                    timerStatus: "idle",
                    timerStartedAt: nil,
                    timerAccumulatedSeconds: 0,
                    rpe: nil,
                    isCompleted: false,
                    completedAt: nil,
                    restSeconds: last?.restSeconds ?? exercise.restSeconds,
                    note: last?.note
                )
            }
            _ = try await FitnessAPIClient.saveSessionStructure(id: payload.sessionId, request: request)
            await load()
        } catch {
            errorMessage = "添加组失败，请检查网络"
        }
    }

    func updateSetValues(exerciseId: Int, setId: Int, actualWeightKg: Double?, actualReps: Int?, actualDurationSeconds: Int?, actualDistanceMeters: Double?) async {
        guard let detail, !updatingSetIds.contains(setId) else { return }
        updatingSetIds.insert(setId)
        errorMessage = nil
        defer { updatingSetIds.remove(setId) }
        do {
            let request = makeStructureRequest(from: detail) { exercise, set in
                guard set.sessionSetId == setId else {
                    return sessionSetRequest(from: set, exercise: exercise)
                }
                return FitnessSessionSetRequest(
                    sessionSetId: set.sessionSetId,
                    setOrder: set.setOrder,
                    setType: set.setType,
                    plannedWeightKg: set.plannedWeightKg,
                    plannedReps: set.plannedReps,
                    plannedDurationSeconds: set.plannedDurationSeconds,
                    plannedDistanceMeters: set.plannedDistanceMeters,
                    actualWeightKg: actualWeightKg,
                    actualReps: actualReps,
                    actualDurationSeconds: actualDurationSeconds,
                    actualDistanceMeters: actualDistanceMeters,
                    timerStatus: set.timerStatus ?? "idle",
                    timerStartedAt: set.timerStartedAt.map { Self.isoFormatter.string(from: $0) },
                    timerAccumulatedSeconds: set.timerAccumulatedSeconds ?? 0,
                    rpe: set.rpe,
                    isCompleted: set.isCompleted,
                    completedAt: set.completedAt.map { Self.isoFormatter.string(from: $0) },
                    restSeconds: set.restSeconds ?? exercise.restSeconds,
                    note: set.note
                )
            }
            _ = try await FitnessAPIClient.saveSessionStructure(id: payload.sessionId, request: request)
            await load()
        } catch {
            errorMessage = "保存失败，请检查网络"
        }
    }

    func deleteSetFromSession(exerciseId: Int, setId: Int) async {
        guard let detail else { return }
        errorMessage = nil
        do {
            let exerciseRequests = detail.exercises.map { exercise in
                let sets = exercise.sets.filter { $0.sessionSetId != setId }
                    .enumerated()
                    .map { idx, s -> FitnessSessionSetRequest in
                        var req = sessionSetRequest(from: s, exercise: exercise)
                        return FitnessSessionSetRequest(
                            sessionSetId: req.sessionSetId,
                            setOrder: idx + 1,
                            setType: req.setType,
                            plannedWeightKg: req.plannedWeightKg, plannedReps: req.plannedReps,
                            plannedDurationSeconds: req.plannedDurationSeconds, plannedDistanceMeters: req.plannedDistanceMeters,
                            actualWeightKg: req.actualWeightKg, actualReps: req.actualReps,
                            actualDurationSeconds: req.actualDurationSeconds, actualDistanceMeters: req.actualDistanceMeters,
                            timerStatus: req.timerStatus, timerStartedAt: req.timerStartedAt,
                            timerAccumulatedSeconds: req.timerAccumulatedSeconds,
                            rpe: req.rpe, isCompleted: req.isCompleted, completedAt: req.completedAt,
                            restSeconds: req.restSeconds, note: req.note
                        )
                    }
                return FitnessSessionExerciseRequest(
                    sessionExerciseId: exercise.sessionExerciseId,
                    exerciseId: exercise.exerciseId,
                    sortOrder: exercise.sortOrder,
                    restSeconds: exercise.restSeconds,
                    note: exercise.note,
                    sets: sets
                )
            }
            let request = FitnessSessionStructureRequest(
                exercises: exerciseRequests,
                deletedSessionExerciseIds: [],
                deletedSessionSetIds: [setId]
            )
            _ = try await FitnessAPIClient.saveSessionStructure(id: payload.sessionId, request: request)
            await load()
        } catch {
            errorMessage = "删除组失败，请检查网络"
        }
    }

    func deleteExerciseFromSession(exerciseId: Int) async {
        guard let detail, !savingExerciseIds.contains(exerciseId) else { return }
        savingExerciseIds.insert(exerciseId)
        errorMessage = nil
        defer { savingExerciseIds.remove(exerciseId) }
        do {
            let remainingExercises = detail.exercises.filter { $0.sessionExerciseId != exerciseId }
            let exerciseRequests = remainingExercises.map { exercise in
                FitnessSessionExerciseRequest(
                    sessionExerciseId: exercise.sessionExerciseId,
                    exerciseId: exercise.exerciseId,
                    sortOrder: exercise.sortOrder,
                    restSeconds: exercise.restSeconds,
                    note: exercise.note,
                    sets: exercise.sets.map { sessionSetRequest(from: $0, exercise: exercise) }
                )
            }
            let request = FitnessSessionStructureRequest(
                exercises: exerciseRequests,
                deletedSessionExerciseIds: [exerciseId],
                deletedSessionSetIds: []
            )
            _ = try await FitnessAPIClient.saveSessionStructure(id: payload.sessionId, request: request)
            await load()
        } catch {
            errorMessage = "删除动作失败，请检查网络"
        }
    }

    func addExercisesToSession(_ selected: [FitnessExercise]) async {
        guard let detail, !isAddingExercise else { return }
        let existingExerciseIds = Set(detail.exercises.map { $0.exerciseId })
        let newExercises = selected.filter { !existingExerciseIds.contains($0.id) }
        guard !newExercises.isEmpty else { return }

        isAddingExercise = true
        errorMessage = nil
        defer { isAddingExercise = false }

        do {
            var exerciseRequests = detail.exercises
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { exercise in
                    FitnessSessionExerciseRequest(
                        sessionExerciseId: exercise.sessionExerciseId,
                        exerciseId: exercise.exerciseId,
                        sortOrder: exercise.sortOrder,
                        restSeconds: exercise.restSeconds,
                        note: exercise.note,
                        sets: exercise.sets.map { sessionSetRequest(from: $0, exercise: exercise) }
                    )
                }

            let nextSortOrder = (exerciseRequests.map(\.sortOrder).max() ?? 0) + 1
            let appended = newExercises.enumerated().map { offset, exercise in
                FitnessSessionExerciseRequest(
                    sessionExerciseId: nil,
                    exerciseId: exercise.id,
                    sortOrder: nextSortOrder + offset,
                    restSeconds: 120,
                    note: nil,
                    sets: [defaultSessionSetRequest(for: exercise)]
                )
            }
            exerciseRequests.append(contentsOf: appended)

            let request = FitnessSessionStructureRequest(
                exercises: exerciseRequests,
                deletedSessionExerciseIds: [],
                deletedSessionSetIds: []
            )
            _ = try await FitnessAPIClient.saveSessionStructure(id: payload.sessionId, request: request)
            await load()
        } catch {
            errorMessage = "添加动作失败，请检查网络"
        }
    }

    func startNextSet() async {
        guard let target = nextStartTarget() else { return }
        await toggleSetCompletion(exerciseId: target.exerciseId, setId: target.setId)
    }

    func handleMiniPlayerAction() async {
        await waitForPendingSetUpdates()
        if isSessionPaused {
            await resumeSession()
            return
        }
        guard let detail else { return }
        let contexts = orderedSetContexts(from: detail)
        if let running = contexts.first(where: { $0.set.timerStatus == "running" }) {
            await toggleSetCompletion(exerciseId: running.exercise.sessionExerciseId, setId: running.set.sessionSetId)
            return
        }
        await startNextSet()
    }

    func waitForPendingSetUpdates() async {
        try? await Task.sleep(nanoseconds: 150_000_000)
        while !updatingSetIds.isEmpty {
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
    }

    func pauseSession() async {
        guard !isSessionPaused, !isPausing else { return }
        isSessionPaused = true
        sessionPausedAt = Date()
        await pauseCurrentSet()
    }

    func resumeSession() async {
        guard isSessionPaused else { return }
        let pausedTarget = detail.map { detail in
            orderedSetContexts(from: detail).first { $0.set.timerStatus == "paused" && !$0.set.isCompleted }
        } ?? nil
        if let pausedAt = sessionPausedAt {
            accumulatedSessionPauseSeconds += max(0, Int(Date().timeIntervalSince(pausedAt)))
        }
        sessionPausedAt = nil
        isSessionPaused = false
        if let pausedTarget {
            await toggleSetCompletion(exerciseId: pausedTarget.exercise.sessionExerciseId, setId: pausedTarget.set.sessionSetId)
        }
    }

    private func pauseCurrentSet() async {
        guard let detail else { return }
        let contexts = orderedSetContexts(from: detail)
        guard let running = contexts.first(where: { $0.set.timerStatus == "running" }) else { return }
        await pauseSet(setId: running.set.sessionSetId)
    }

    func pauseSet(setId: Int) async {
        guard let detail, !isPausing, !savingSetIds.contains(setId) else { return }
        let contexts = orderedSetContexts(from: detail)
        guard let running = contexts.first(where: { $0.set.sessionSetId == setId && $0.set.timerStatus == "running" }) else { return }
        isPausing = true
        savingSetIds.insert(running.set.sessionSetId)
        errorMessage = nil
        defer {
            isPausing = false
            savingSetIds.remove(running.set.sessionSetId)
        }
        do {
            let now = Date()
            let elapsed = running.set.timerStartedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
            let accumulated = (running.set.timerAccumulatedSeconds ?? 0) + elapsed
            let request = makeStructureRequest(from: detail) { exercise, set in
                guard set.sessionSetId == running.set.sessionSetId else {
                    return sessionSetRequest(from: set, exercise: exercise)
                }
                return sessionSetRequest(
                    from: set,
                    exercise: exercise,
                    timerStatusOverride: "paused",
                    timerAccumulatedSecondsOverride: accumulated
                )
            }
            _ = try await FitnessAPIClient.saveSessionStructure(id: payload.sessionId, request: request)
            await load()
        } catch {
            errorMessage = "暂停训练失败，请检查网络"
        }
    }

    func complete(rpe: Double? = nil) async -> Bool {
        guard !isCompleting else { return false }
        isCompleting = true
        errorMessage = nil
        defer { isCompleting = false }
        do {
            _ = try await FitnessAPIClient.completeSession(id: payload.sessionId, rpe: rpe)
            return true
        } catch {
            errorMessage = "完成训练失败，请检查网络"
            return false
        }
    }

    func discard() async -> Bool {
        guard !isDiscarding else { return false }
        isDiscarding = true
        errorMessage = nil
        defer { isDiscarding = false }
        do {
            _ = try await FitnessAPIClient.discardSession(id: payload.sessionId)
            return true
        } catch {
            errorMessage = "删除训练失败，请检查网络"
            return false
        }
    }

    private func nextStartTarget() -> (exerciseId: Int, setId: Int)? {
        guard let detail else { return nil }
        let contexts = orderedSetContexts(from: detail)
        // Same rule the mini player uses so the play button always starts whatever
        // the mini player shows: keep advancing within the current exercise until
        // it's finished, then fall back to any earlier skipped exercise.
        guard let next = fitnessNextTargetContext(in: contexts) else { return nil }
        return (next.exercise.sessionExerciseId, next.set.sessionSetId)
    }

    private func orderedSetContexts(from detail: FitnessSessionDetail) -> [(exercise: FitnessSessionExercise, set: FitnessSessionSet)] {
        detail.exercises
            .sorted { $0.sortOrder < $1.sortOrder }
            .flatMap { exercise in
                exercise.sets
                    .sorted { $0.setOrder < $1.setOrder }
                    .map { (exercise: exercise, set: $0) }
            }
    }

    private func makeStructureRequest(
        from detail: FitnessSessionDetail,
        setMapper: (FitnessSessionExercise, FitnessSessionSet) -> FitnessSessionSetRequest,
        appendedSetForExerciseId: ((FitnessSessionExercise) -> FitnessSessionSetRequest?)? = nil
    ) -> FitnessSessionStructureRequest {
        let exerciseRequests = detail.exercises.map { exercise in
            var setRequests = exercise.sets.map { setMapper(exercise, $0) }
            if let appendedSet = appendedSetForExerciseId?(exercise) {
                setRequests.append(appendedSet)
            }
            return FitnessSessionExerciseRequest(
                sessionExerciseId: exercise.sessionExerciseId,
                exerciseId: exercise.exerciseId,
                sortOrder: exercise.sortOrder,
                restSeconds: exercise.restSeconds,
                note: exercise.note,
                sets: setRequests
            )
        }
        return FitnessSessionStructureRequest(
            exercises: exerciseRequests,
            deletedSessionExerciseIds: [],
            deletedSessionSetIds: []
        )
    }

    private func sessionSetRequest(
        from set: FitnessSessionSet,
        exercise: FitnessSessionExercise,
        isCompletedOverride: Bool? = nil,
        completedAtOverride: String? = nil,
        clearCompletedAt: Bool = false,
        timerStatusOverride: String? = nil,
        timerStartedAtOverride: String? = nil,
        clearTimerStartedAt: Bool = false,
        timerAccumulatedSecondsOverride: Int? = nil,
        actualDurationSecondsOverride: Int? = nil
    ) -> FitnessSessionSetRequest {
        let isCompleted = isCompletedOverride ?? set.isCompleted
        let completedAt = clearCompletedAt
            ? nil
            : (isCompleted
                ? (completedAtOverride ?? set.completedAt.map { Self.isoFormatter.string(from: $0) } ?? Self.isoFormatter.string(from: .now))
                : nil)
        let timerStartedAt = clearTimerStartedAt
            ? nil
            : (timerStartedAtOverride ?? set.timerStartedAt.map { Self.isoFormatter.string(from: $0) })
        return FitnessSessionSetRequest(
            sessionSetId: set.sessionSetId,
            setOrder: set.setOrder,
            setType: set.setType,
            plannedWeightKg: set.plannedWeightKg,
            plannedReps: set.plannedReps,
            plannedDurationSeconds: set.plannedDurationSeconds,
            plannedDistanceMeters: set.plannedDistanceMeters,
            actualWeightKg: isCompleted ? (set.actualWeightKg ?? set.plannedWeightKg) : set.actualWeightKg,
            actualReps: isCompleted ? (set.actualReps ?? set.plannedReps) : set.actualReps,
            actualDurationSeconds: isCompleted ? (actualDurationSecondsOverride ?? set.actualDurationSeconds ?? set.plannedDurationSeconds) : set.actualDurationSeconds,
            actualDistanceMeters: isCompleted ? (set.actualDistanceMeters ?? set.plannedDistanceMeters) : set.actualDistanceMeters,
            timerStatus: timerStatusOverride ?? set.timerStatus ?? "idle",
            timerStartedAt: timerStartedAt,
            timerAccumulatedSeconds: timerAccumulatedSecondsOverride ?? set.timerAccumulatedSeconds ?? 0,
            rpe: set.rpe,
            isCompleted: isCompleted,
            completedAt: completedAt,
            restSeconds: set.restSeconds ?? exercise.restSeconds,
            note: set.note
        )
    }

    private func defaultSessionSetRequest(for exercise: FitnessExercise) -> FitnessSessionSetRequest {
        FitnessSessionSetRequest(
            sessionSetId: nil,
            setOrder: 1,
            setType: "normal",
            plannedWeightKg: exercise.trackingType == "weight_reps" ? 10 : nil,
            plannedReps: exercise.isTimeBased ? nil : 12,
            plannedDurationSeconds: exercise.isTimeBased ? 30 : nil,
            plannedDistanceMeters: ExerciseTrackingDisplay.isDistanceBased(exercise.trackingType) ? 100 : nil,
            actualWeightKg: nil,
            actualReps: nil,
            actualDurationSeconds: nil,
            actualDistanceMeters: nil,
            timerStatus: "idle",
            timerStartedAt: nil,
            timerAccumulatedSeconds: 0,
            rpe: nil,
            isCompleted: false,
            completedAt: nil,
            restSeconds: 120,
            note: nil
        )
    }
}

struct FitnessActiveSessionView: View {
    let payload: FitnessWorkoutSessionPayload
    let onCompleted: () async -> Void

    @StateObject private var vm: FitnessActiveSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var restVisibleExerciseIds: Set<Int> = []
    @State private var remindedRestSetIds: Set<Int> = []
    @State private var showDiscardConfirm = false
    @State private var showExerciseLibrary = false
    @State private var progressTarget: ExerciseProgressTarget?
    @State private var showRatingSheet = false
    @State private var ratingValue: Double = 5
    @State private var showIncompleteAlert = false
    @State private var editingSetId: Int?

    init(payload: FitnessWorkoutSessionPayload, onCompleted: @escaping () async -> Void) {
        self.payload = payload
        self.onCompleted = onCompleted
        _vm = StateObject(wrappedValue: FitnessActiveSessionViewModel(payload: payload))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.white.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        activeHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                            .padding(.bottom, 18)

                        if vm.isLoading && vm.detail == nil {
                            ProgressView()
                                .padding(.top, 48)
                        } else if let detail = vm.detail {
                            let contexts = orderedSetContexts(from: detail)
                            let latestCompletedSetId = contexts
                                .filter { $0.set.isCompleted }
                                .max { ($0.set.completedAt ?? .distantPast) < ($1.set.completedAt ?? .distantPast) }?
                                .set.sessionSetId
                            ForEach(Array(detail.exercises.enumerated()), id: \.element.id) { index, exercise in
                                exerciseCard(exercise, contexts: contexts, latestCompletedSetId: latestCompletedSetId, totalCount: detail.exercises.count, index: index)
                            }

                            addExerciseButton
                                .padding(.horizontal, 16)
                                .padding(.top, 6)
                        } else if let errorMessage = vm.errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color(hex: "F05B5B"))
                                .padding(.top, 48)
                        }
                    }
                    .padding(.bottom, 118)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: editingSetId) { _, setId in
                    guard let setId else { return }
                    // Lift the tapped field to a comfortable middle-slightly-above
                    // position (not jammed against the top) so the keyboard doesn't
                    // cover it.
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("set-\(setId)", anchor: UnitPoint(x: 0.5, y: 0.35))
                    }
                }
            }
            // Select all text when a field begins editing so the user can type a
            // new value straight away instead of clearing the old one first.
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { notification in
                guard let textField = notification.object as? UITextField else { return }
                DispatchQueue.main.async {
                    textField.selectAll(nil)
                }
            }

            miniPlayer
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await vm.load() }
        .sheet(isPresented: $showExerciseLibrary) {
            FitnessExerciseLibrarySheet(
                preselectedIds: Set(vm.detail?.exercises.map { $0.exerciseId } ?? [])
            ) { selected in
                Task { await vm.addExercisesToSession(selected) }
            }
        }
        .sheet(item: $progressTarget) { target in
            ExerciseProgressSheet(target: target)
        }
        .fullScreenCover(isPresented: $showRatingSheet) {
            WorkoutRatingSheet(rpe: $ratingValue) {
                showRatingSheet = false
                Task {
                    if await vm.complete(rpe: ratingValue) {
                        await onCompleted()
                        dismiss()
                    }
                }
            }
        }
        .alert("错误", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("好") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .alert("还有未完成的组", isPresented: $showIncompleteAlert) {
            Button("继续训练", role: .cancel) {}
            Button("仍然完成", role: .destructive) { showRatingSheet = true }
        } message: {
            Text("还有 \(vm.incompleteSetCount) 组未完成，确定要结束训练吗？")
        }
        .confirmationDialog("删除本次训练？", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("删除训练", role: .destructive) {
                Task {
                    if await vm.discard() {
                        await onCompleted()
                        dismiss()
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后不会保存为完成记录。")
        }
    }

    @ViewBuilder
    private func exerciseCard(
        _ exercise: FitnessSessionExercise,
        contexts: [(exercise: FitnessSessionExercise, set: FitnessSessionSet)],
        latestCompletedSetId: Int?,
        totalCount: Int,
        index: Int
    ) -> some View {
        let exId = exercise.sessionExerciseId
        FitnessActiveExerciseCard(
            exercise: exercise,
            savingSetIds: vm.savingSetIds,
            isAddingSet: vm.savingExerciseIds.contains(exId),
            isRestVisible: restVisibleExerciseIds.contains(exId),
            latestCompletedSetId: latestCompletedSetId,
            nextSetForRest: { setId in nextSet(after: setId, in: contexts) },
            onToggleRest: {
                if restVisibleExerciseIds.contains(exId) { restVisibleExerciseIds.remove(exId) }
                else { restVisibleExerciseIds.insert(exId) }
            },
            onProgress: {
                progressTarget = ExerciseProgressTarget(exerciseId: exercise.exerciseId, name: exercise.name, trackingType: exercise.trackingType)
            },
            onToggleSet: { setId in Task { await vm.toggleSetCompletion(exerciseId: exId, setId: setId) } },
            onPauseSet: { setId in Task { await vm.pauseSet(setId: setId) } },
            onAddSet: { Task { await vm.addSet(to: exId) } },
            onDeleteExercise: { Task { await vm.deleteExerciseFromSession(exerciseId: exId) } },
            onDeleteSet: { setId in Task { await vm.deleteSetFromSession(exerciseId: exId, setId: setId) } },
            onUpdateSet: { setId, w, r, d, dist in Task { await vm.updateSetValues(exerciseId: exId, setId: setId, actualWeightKg: w, actualReps: r, actualDurationSeconds: d, actualDistanceMeters: dist) } },
            onRestDue: { set in
                playRestReminder(for: set.sessionSetId)
            },
            onEditSet: { setId in editingSetId = setId }
        )
        .padding(.horizontal, 16)

        if index < totalCount - 1 {
            ActiveExerciseConnector().padding(.vertical, 2)
        }
    }

    private var addExerciseButton: some View {
        Button {
            showExerciseLibrary = true
        } label: {
            HStack(spacing: 12) {
                Text("添加锻炼")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: "6F6F76"))

                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: 54, height: 54)
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    if vm.isAddingExercise {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                    }
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .frame(height: 88)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.42))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(hex: "CFCFD6"), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(vm.isAddingExercise)
    }

    private var activeHeader: some View {
        HStack(alignment: .top) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.elapsedText(seconds: vm.elapsedSeconds(at: context.date)))
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                    Text(vm.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "6F6F76"))
                }
            }

            Spacer()

            Button {
                if vm.isCompleting { return }
                if vm.incompleteSetCount > 0 {
                    showIncompleteAlert = true
                } else {
                    showRatingSheet = true
                }
            } label: {
                Group {
                    if vm.isCompleting {
                        ProgressView()
                            .tint(Color(hex: "F05B5B"))
                    } else {
                        Text("完成")
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                .foregroundStyle(Color(hex: "F05B5B"))
                .frame(width: 82, height: 52)
                .background(Color(hex: "FFE3DC"), in: Capsule())
            }
            .disabled(vm.isCompleting)

            Menu {
                Button {
                    Task {
                        if vm.isSessionPaused {
                            await vm.resumeSession()
                        } else {
                            await vm.pauseSession()
                        }
                    }
                } label: {
                    Label(vm.isSessionPaused ? "继续训练" : "暂停训练", systemImage: vm.isSessionPaused ? "play.fill" : "pause.fill")
                }
                .disabled(vm.isPausing)

                Button(role: .destructive) {
                    showDiscardConfirm = true
                } label: {
                    Label("删除训练", systemImage: "trash")
                }
                .disabled(vm.isDiscarding)
            } label: {
                Circle()
                    .fill(.white)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Text("···")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                            .offset(y: -3)
                    )
            }
        }
    }

    private var miniPlayer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let state = miniPlayerState(now: context.date)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(state.prefix)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(state.tint)
                        Text(state.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                            .lineLimit(1)
                    }

                    Text(state.timeText)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(hex: "6F6F76"))
                }

                Spacer()

                Image(systemName: "minus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "8E8E93"))

                Image(systemName: "heart.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "A8A8AD"))

                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    Task { await vm.handleMiniPlayerAction() }
                } label: {
                    Circle()
                        .fill(state.actionFill)
                        .frame(width: 56, height: 56)
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                        .overlay(
                            Image(systemName: state.actionSymbol)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(state.actionForeground)
                                .offset(x: state.actionSymbol == "play.fill" ? 2 : 0)
                        )
                }
                .disabled(state.actionDisabled)
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .frame(height: 72)
            .background(.ultraThinMaterial, in: Capsule())
            .onChange(of: state.restDueSetId) { _, setId in
                if let setId {
                    playRestReminder(for: setId)
                }
            }
            .onAppear {
                if let setId = state.restDueSetId {
                    playRestReminder(for: setId)
                }
            }
        }
    }

    private static func elapsedText(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func miniPlayerState(now: Date) -> MiniPlayerState {
        guard let detail = vm.detail else {
            return MiniPlayerState(
                title: vm.title,
                prefix: "----",
                timeText: "00:00",
                tint: Color(hex: "4B8CFF"),
                actionSymbol: "play.fill",
                actionFill: .white,
                actionForeground: Color(hex: "1C1C1E"),
                actionDisabled: true,
                restDueSetId: nil
            )
        }

        let contexts = orderedSetContexts(from: detail)
        if vm.isSessionPaused {
            let paused = contexts.first { $0.set.timerStatus == "paused" && !$0.set.isCompleted }
            let title = paused?.exercise.name ?? detail.name
            return MiniPlayerState(
                title: title,
                prefix: "训练暂停",
                timeText: paused.map { Self.clockText($0.set.timerAccumulatedSeconds ?? 0) } ?? Self.clockText(vm.elapsedSeconds(at: now)),
                tint: Color(hex: "8E8E93"),
                actionSymbol: "play.fill",
                actionFill: .white,
                actionForeground: Color(hex: "1C1C1E"),
                actionDisabled: vm.isPausing,
                restDueSetId: nil
            )
        }

        if let running = contexts.first(where: { $0.set.timerStatus == "running" }) {
            let base = running.set.timerAccumulatedSeconds ?? 0
            let live = running.set.timerStartedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
            return MiniPlayerState(
                title: running.exercise.name,
                prefix: "运动",
                timeText: Self.clockText(base + live),
                tint: Color(hex: "FF7847"),
                actionSymbol: "checkmark",
                actionFill: Color(hex: "34C982"),
                actionForeground: .white,
                actionDisabled: vm.savingSetIds.contains(running.set.sessionSetId),
                restDueSetId: nil
            )
        }

        if let paused = contexts.first(where: { $0.set.timerStatus == "paused" && !$0.set.isCompleted }) {
            return MiniPlayerState(
                title: paused.exercise.name,
                prefix: "暂停",
                timeText: Self.clockText(paused.set.timerAccumulatedSeconds ?? 0),
                tint: Color(hex: "8E8E93"),
                actionSymbol: "play.fill",
                actionFill: .white,
                actionForeground: Color(hex: "1C1C1E"),
                actionDisabled: vm.savingSetIds.contains(paused.set.sessionSetId),
                restDueSetId: nil
            )
        }

        // Rest countdown is driven by the set completed most recently (by timestamp),
        // not by list position, so it works even when the user trains out of order.
        // This runs regardless of whether the per-set rest timer is expanded, so the
        // reminder counts down and fires in the background without the user tapping.
        let lastCompleted = contexts
            .filter { $0.set.isCompleted }
            .max { ($0.set.completedAt ?? .distantPast) < ($1.set.completedAt ?? .distantPast) }
        if let lastCompleted,
           let completedAt = lastCompleted.set.completedAt,
           let next = fitnessNextTargetContext(in: contexts) {
            if !hasSetStarted(next.set) {
                let restSeconds = lastCompleted.set.restSeconds ?? lastCompleted.exercise.restSeconds
                let elapsed = max(0, Int(now.timeIntervalSince(completedAt)))
                let remaining = max(0, restSeconds - elapsed)
                return MiniPlayerState(
                    title: next.exercise.name,
                    prefix: remaining == 0 ? "休息完成" : "休息",
                    timeText: Self.clockText(remaining),
                    tint: remaining == 0 ? Color(hex: "34C982") : Color(hex: "4B8CFF"),
                    actionSymbol: "play.fill",
                    actionFill: remaining == 0 ? Color(hex: "34C982") : .white,
                    actionForeground: remaining == 0 ? .white : Color(hex: "1C1C1E"),
                    actionDisabled: false,
                    restDueSetId: remaining == 0 ? lastCompleted.set.sessionSetId : nil
                )
            }
        }

        let next = contexts.first { !$0.set.isCompleted && $0.set.timerStatus != "running" }
        return MiniPlayerState(
            title: next?.exercise.name ?? detail.name,
            prefix: "准备",
            timeText: "00:00",
            tint: Color(hex: "4B8CFF"),
            actionSymbol: "play.fill",
            actionFill: .white,
            actionForeground: Color(hex: "1C1C1E"),
            actionDisabled: next == nil,
            restDueSetId: nil
        )
    }

    private func playRestReminder(for setId: Int) {
        guard !remindedRestSetIds.contains(setId) else { return }
        remindedRestSetIds.insert(setId)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1005)
    }

    private func hasSetStarted(_ set: FitnessSessionSet) -> Bool {
        set.timerStartedAt != nil
            || (set.timerAccumulatedSeconds ?? 0) > 0
            || set.timerStatus == "running"
            || set.timerStatus == "paused"
            || set.isCompleted
    }

    private func orderedSetContexts(from detail: FitnessSessionDetail) -> [(exercise: FitnessSessionExercise, set: FitnessSessionSet)] {
        detail.exercises
            .sorted { $0.sortOrder < $1.sortOrder }
            .flatMap { exercise in
                exercise.sets
                    .sorted { $0.setOrder < $1.setOrder }
                    .map { (exercise: exercise, set: $0) }
            }
    }

    private func nextSet(
        after setId: Int,
        in contexts: [(exercise: FitnessSessionExercise, set: FitnessSessionSet)]
    ) -> FitnessSessionSet? {
        guard let index = contexts.firstIndex(where: { $0.set.sessionSetId == setId }) else { return nil }
        return contexts.dropFirst(index + 1).first?.set
    }

    private static func clockText(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private struct MiniPlayerState {
        let title: String
        let prefix: String
        let timeText: String
        let tint: Color
        let actionSymbol: String
        let actionFill: Color
        let actionForeground: Color
        let actionDisabled: Bool
        let restDueSetId: Int?
    }
}

struct ExerciseProgressTarget: Identifiable, Hashable {
    let exerciseId: Int
    let name: String
    let trackingType: String

    var id: Int { exerciseId }
}

@MainActor
private final class ExerciseProgressViewModel: ObservableObject {
    let target: ExerciseProgressTarget
    @Published private(set) var progress: ExerciseProgressResponse?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedRange: String = "30d"

    init(target: ExerciseProgressTarget) {
        self.target = target
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            progress = try await FitnessAPIClient.exerciseProgress(exerciseId: target.exerciseId, range: selectedRange)
        } catch {
            errorMessage = "历史记录加载失败"
        }
    }

    func changeRange(_ range: String) async {
        selectedRange = range
        progress = nil
        await load()
    }
}

struct ExerciseProgressSheet: View {
    let target: ExerciseProgressTarget
    @StateObject private var vm: ExerciseProgressViewModel
    @Environment(\.dismiss) private var dismiss

    init(target: ExerciseProgressTarget) {
        self.target = target
        _vm = StateObject(wrappedValue: ExerciseProgressViewModel(target: target))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    rangePickerBar
                        .padding(.top, 4)

                    if vm.isLoading && vm.progress == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 42)
                    } else if let p = vm.progress, p.history.isEmpty {
                        emptyState
                    } else if let p = vm.progress {
                        summaryCard(p.summary, history: p.history, display: p.display)
                        let series = chartSeries(items: p.items, history: p.history, display: p.display)
                        if !series.isEmpty {
                            trendSection(series, display: p.display)
                        }
                        historySection(p.history, display: p.display)
                    } else if let msg = vm.errorMessage {
                        Label(msg, systemImage: "exclamationmark.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: "F05B5B"))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 42)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(Color(hex: "F7F7FA").ignoresSafeArea())
            .navigationTitle(target.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await vm.load() }
    }

    // MARK: Range picker

    private var rangePickerBar: some View {
        HStack(spacing: 8) {
            ForEach([("30d", "30天"), ("90d", "90天"), ("1y", "1年")], id: \.0) { range, label in
                Button {
                    Task { await vm.changeRange(range) }
                } label: {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(vm.selectedRange == range ? .white : Color(hex: "6F6F76"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            vm.selectedRange == range ? Color(hex: "FF7847") : Color(hex: "ECECEF"),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color(hex: "8E8E93"))
            Text("暂无历史记录")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(hex: "1C1C1E"))
            Text("完成几次包含该动作的训练后，这里会显示进展趋势和历史记录。")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "6F6F76"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 42)
    }

    private func effectiveKind(_ display: ExerciseProgressDisplayConfig) -> String {
        display.metricKind
    }

    private func chartSeries(
        items: [ExerciseProgressPoint],
        history: [ExerciseHistorySessionItem],
        display: ExerciseProgressDisplayConfig
    ) -> [(String, Double)] {
        items.map { ($0.date, $0.value) }
    }

    // MARK: Summary card

    private func summaryCard(_ summary: ExerciseProgressSummaryData, history: [ExerciseHistorySessionItem], display: ExerciseProgressDisplayConfig) -> some View {
        VStack(spacing: 12) {
            heroRow(summary, history: history, display: display)
            Divider()
            statsGrid(summary, display: display)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: "ECECEF"), lineWidth: 1))
    }

    @ViewBuilder
    private func heroRow(_ summary: ExerciseProgressSummaryData, history: [ExerciseHistorySessionItem], display: ExerciseProgressDisplayConfig) -> some View {
        let kind = effectiveKind(display)
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(heroLabel(kind))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "8E8E93"))
                heroValueView(summary, history: history, kind: kind)
            }
            Spacer()
            changeBadge(summary.changePercent, kind: kind)
        }
    }

    @ViewBuilder
    private func heroValueView(_ summary: ExerciseProgressSummaryData, history: [ExerciseHistorySessionItem], kind: String) -> some View {
        switch kind {
        case "distance":
            // Prefer latest session's total distance; fall back to summary best
            let v = history.first?.totalDistanceMeters.flatMap { $0 > 0 ? $0 : nil }
                ?? summary.bestDistanceMeters
            if let dist = v {
                Text(Self.distanceText(dist))
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Color(hex: "1C1C1E"))
            } else {
                Text("--").font(.system(size: 30, weight: .heavy)).foregroundStyle(Color(hex: "1C1C1E"))
            }
        case "duration":
            let v = history.first?.totalDurationSeconds.flatMap { $0 > 0 ? $0 : nil }
                ?? summary.bestDurationSeconds
            if let dur = v {
                Text(Self.durationText(dur))
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Color(hex: "1C1C1E"))
            } else {
                Text("--").font(.system(size: 30, weight: .heavy)).foregroundStyle(Color(hex: "1C1C1E"))
            }
        default:
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(summary.latestMetricValue.map { Self.cleanNumber($0) } ?? "--")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Text("kg")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "8E8E93"))
            }
        }
    }

    @ViewBuilder
    private func changeBadge(_ changePercent: Double?, kind: String) -> some View {
        // For cardio, the backend's changePercent is computed from estimated_1rm (= 0),
        // so it's meaningless — don't show it.
        if let pct = changePercent, kind != "distance" && kind != "duration" {
            let isUp = pct >= 0
            HStack(spacing: 4) {
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                Text(String(format: "%+.1f%%", pct))
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(isUp ? Color(hex: "30C46E") : Color(hex: "F05B5B"))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (isUp ? Color(hex: "30C46E") : Color(hex: "F05B5B")).opacity(0.1),
                in: Capsule()
            )
        }
    }

    @ViewBuilder
    private func statsGrid(_ summary: ExerciseProgressSummaryData, display: ExerciseProgressDisplayConfig) -> some View {
        let cells = statCells(summary, display: display)
        HStack(spacing: 0) {
            ForEach(cells.indices, id: \.self) { i in
                summaryStatCell(value: cells[i].0, label: cells[i].1)
                if i < cells.count - 1 {
                    Divider().frame(height: 32)
                }
            }
        }
    }

    private func statCells(_ summary: ExerciseProgressSummaryData, display: ExerciseProgressDisplayConfig) -> [(String, String)] {
        if display.usesDistance && display.usesDuration {
            return [
                (summary.bestDistanceMeters.map(Self.distanceText) ?? "--", "最远距离"),
                (summary.bestDurationSeconds.map(Self.durationText) ?? "--", "最长用时"),
                (summary.totalDistanceMeters.map(Self.distanceText) ?? "--", "累计距离"),
                ("\(summary.sessionCount)", "训练次数")
            ]
        }
        if display.usesDuration {
            return [
                (summary.bestDurationSeconds.map(Self.durationText) ?? "--", "最长时长"),
                (summary.totalDurationSeconds.map(Self.durationText) ?? "--", "累计时长"),
                ("\(summary.completedSetCount)", "完成组数"),
                ("\(summary.sessionCount)", "训练次数")
            ]
        }
        return [
            (summary.bestWeightKg.map { "\(Self.cleanNumber($0)) kg" } ?? "--", "最大重量"),
            (summary.bestReps.map { "\($0) 次" } ?? "--", "最多次数"),
            (summary.totalVolumeKg.map { $0 >= 1000 ? String(format: "%.1ft", $0/1000) : "\(Int($0))kg" } ?? "--", "总训练量"),
            ("\(summary.sessionCount)", "训练次数")
        ]
    }

    private func summaryStatCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "8E8E93"))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Trend chart

    private func trendSection(_ series: [(String, Double)], display: ExerciseProgressDisplayConfig) -> some View {
        let kind = effectiveKind(display)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("进展趋势")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Spacer()
                if series.count > 1 {
                    Text("\(Self.shortDateStr(series.first?.0 ?? "")) – \(Self.shortDateStr(series.last?.0 ?? ""))")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "8E8E93"))
                }
            }
            ProgressTrendChart(
                values: series.map(\.1),
                dates: series.map(\.0),
                metricKind: kind
            )
            .frame(height: 100)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: "ECECEF"), lineWidth: 1))
    }

    // MARK: History sessions

    private func historySection(_ history: [ExerciseHistorySessionItem], display: ExerciseProgressDisplayConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("历史记录")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(hex: "1C1C1E"))
            let visible = Array(history.prefix(10))
            ForEach(visible) { session in
                sessionHistoryRow(session, display: display)
                if session.id != visible.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: "ECECEF"), lineWidth: 1))
    }

    private func sessionHistoryRow(_ session: ExerciseHistorySessionItem, display: ExerciseProgressDisplayConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Text(Self.shortDateStr(session.startedAt ?? ""))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "FF7847"))
                    .frame(minWidth: 44, alignment: .leading)
                Text(session.sessionName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .lineLimit(1)
                Spacer()
                sessionMetricBadge(session, display: display)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(session.sets) { set in
                    sessionSetRow(set, display: display)
                }
            }
            .padding(.leading, 50)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sessionMetricBadge(_ session: ExerciseHistorySessionItem, display: ExerciseProgressDisplayConfig) -> some View {
        if display.usesDistance && display.usesDuration {
            if let dist = session.bestDistanceMeters, let dur = session.bestDurationSeconds {
                Text("\(Self.distanceText(dist)) · \(Self.durationText(dur))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "8E8E93"))
            }
        } else if display.usesDuration {
            if let dur = session.bestDurationSeconds {
                Text(Self.durationText(dur))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "8E8E93"))
            }
        } else {
            if let metric = session.metricValue {
                Text("1RM \(Self.cleanNumber(metric)) kg")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "8E8E93"))
            }
        }
    }

    private func sessionSetRow(_ set: ExerciseHistorySetItem, display: ExerciseProgressDisplayConfig) -> some View {
        HStack(spacing: 6) {
            Text("组\(set.setOrder)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(set.isCompleted ? Color(hex: "FF7847") : Color(hex: "C0C3CC"))
                .frame(width: 24, alignment: .leading)

            Text(setDescription(set, display: display))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(set.isCompleted ? Color(hex: "1C1C1E") : Color(hex: "A0A0A8"))

            if display.metricKind == "estimated_1rm", let rm = set.estimated1Rm, set.isCompleted {
                Spacer()
                Text("≈\(Self.cleanNumber(rm)) kg")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "8E8E93"))
            }
        }
    }

    private func setDescription(_ set: ExerciseHistorySetItem, display: ExerciseProgressDisplayConfig) -> String {
        if display.usesDistance && display.usesDuration {
            let d = set.actualDistanceMeters.map(Self.distanceText) ?? "--"
            let t = set.actualDurationSeconds.map(Self.durationText) ?? "--"
            return "\(d) · \(t)"
        }
        if display.usesDuration {
            return set.actualDurationSeconds.map(Self.durationText) ?? "--"
        }
        if display.usesWeight {
            let w = set.actualWeightKg.map { "\(Self.cleanNumber($0)) kg" } ?? "--"
            let r = set.actualReps.map { "× \($0)" } ?? ""
            return "\(w) \(r)".trimmingCharacters(in: .whitespaces)
        }
        return set.actualReps.map { "\($0) 次" } ?? "--"
    }

    // MARK: Display helpers

    private func heroLabel(_ kind: String) -> String {
        switch kind {
        case "distance": return "最近一次总距离"
        case "duration": return "最近一次总时长"
        case "volume":   return "最近一次总训练量"
        case "weight":   return "最近一次最大重量"
        case "reps":     return "最近一次最多次数"
        default:         return "当前 1RM 估算"
        }
    }

    // MARK: Formatters

    static func cleanNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func durationText(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    static func distanceText(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.2f km", meters / 1000) : "\(Int(meters)) m"
    }

    static func shortDateStr(_ dateStr: String) -> String {
        guard !dateStr.isEmpty else { return "" }
        let parts = String(dateStr.prefix(10)).split(separator: "-")
        guard parts.count >= 3 else { return String(dateStr.prefix(10)) }
        return "\(parts[1])/\(parts[2])"
    }
}

private struct ProgressTrendChart: View {
    let values: [Double]
    let dates: [String]
    let metricKind: String

    var body: some View {
        GeometryReader { proxy in
            let rawMax = values.max() ?? 0
            let rawMin = values.min() ?? 0
            let isFlat = (rawMax - rawMin) < 0.001
            // 数据完全相同时，以实际值为中心上下各留 10% 空间，避免贴底直线
            let displayMin = isFlat ? rawMin * 0.9 : rawMin
            let displayMax = isFlat ? rawMax * 1.1 + 0.001 : rawMax
            let spread = displayMax - displayMin
            let labelH: CGFloat = 14
            let axisW: CGFloat = values.isEmpty ? 0 : axisLabelWidth
            let chartH = proxy.size.height - labelH - 6
            let chartW = proxy.size.width - axisW - 4

            ZStack(alignment: .topLeading) {
                // Y-axis labels
                VStack {
                    Text(isFlat ? formatValue(rawMax) : formatValue(displayMax))
                        .font(.system(size: 9))
                        .foregroundStyle(Color(hex: "B0B0B8"))
                        .frame(width: axisW, alignment: .trailing)
                    Spacer()
                    if !isFlat {
                        Text(formatValue(displayMin))
                            .font(.system(size: 9))
                            .foregroundStyle(Color(hex: "B0B0B8"))
                            .frame(width: axisW, alignment: .trailing)
                    }
                }
                .frame(height: chartH)

                // Chart area
                ZStack(alignment: .bottomLeading) {
                    // Fill
                    Path { path in
                        guard values.count >= 2 else { return }
                        for index in values.indices {
                            let x = chartW * CGFloat(index) / CGFloat(values.count - 1)
                            let ratio = CGFloat((values[index] - displayMin) / spread)
                            let y = chartH - chartH * ratio
                            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        path.addLine(to: CGPoint(x: chartW, y: chartH))
                        path.addLine(to: CGPoint(x: 0, y: chartH))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [Color(hex: "FF7847").opacity(0.15), Color(hex: "FF7847").opacity(0.01)],
                        startPoint: .top, endPoint: .bottom
                    ))

                    // Line
                    Path { path in
                        guard !values.isEmpty else { return }
                        for index in values.indices {
                            let x = values.count == 1 ? chartW / 2 : chartW * CGFloat(index) / CGFloat(values.count - 1)
                            let ratio = CGFloat((values[index] - displayMin) / spread)
                            let y = chartH - chartH * ratio
                            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(Color(hex: "FF7847"), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    // Dot on last point
                    if !values.isEmpty {
                        let lastIdx = values.count - 1
                        let x = values.count == 1 ? chartW / 2 : chartW
                        let ratio = CGFloat((values[lastIdx] - displayMin) / spread)
                        let y = chartH - chartH * ratio
                        ZStack {
                            Circle().fill(Color.white).frame(width: 10, height: 10)
                            Circle().fill(Color(hex: "FF7847")).frame(width: 6, height: 6)
                        }
                        .offset(x: x - 5, y: y - 5)
                    }

                    // Date labels
                    if dates.count >= 2 {
                        HStack {
                            Text(shortDate(dates.first ?? ""))
                                .font(.system(size: 9))
                                .foregroundStyle(Color(hex: "B0B0B8"))
                            Spacer()
                            Text(shortDate(dates.last ?? ""))
                                .font(.system(size: 9))
                                .foregroundStyle(Color(hex: "B0B0B8"))
                        }
                        .offset(y: chartH + 3)
                    }
                }
                .offset(x: axisW + 4)
            }
        }
    }

    private var axisLabelWidth: CGFloat {
        metricKind == "duration" ? 38 : 32
    }

    private func formatValue(_ v: Double) -> String {
        switch metricKind {
        case "distance":
            return v >= 1000 ? String(format: "%.1fk", v / 1000) : "\(Int(v))m"
        case "duration":
            let s = Int(v)
            let m = s / 60
            if m >= 60 { return String(format: "%dh%02d", m/60, m%60) }
            return String(format: "%d:%02d", m, s % 60)
        default:
            return ExerciseProgressSheet.cleanNumber(v)
        }
    }

    private func shortDate(_ s: String) -> String {
        let p = String(s.prefix(10)).split(separator: "-")
        guard p.count >= 3 else { return "" }
        return "\(p[1])/\(p[2])"
    }
}

private struct FitnessActiveExerciseCard: View {
    let exercise: FitnessSessionExercise
    let savingSetIds: Set<Int>
    let isAddingSet: Bool
    let isRestVisible: Bool
    let latestCompletedSetId: Int?
    let nextSetForRest: (Int) -> FitnessSessionSet?
    let onToggleRest: () -> Void
    let onProgress: () -> Void
    let onToggleSet: (Int) -> Void
    let onPauseSet: (Int) -> Void
    let onAddSet: () -> Void
    let onDeleteExercise: () -> Void
    let onDeleteSet: (Int) -> Void
    let onUpdateSet: (Int, Double?, Int?, Int?, Double?) -> Void
    let onRestDue: (FitnessSessionSet) -> Void
    let onEditSet: (Int?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "F6F6F8"))
                    .frame(width: 58, height: 58)
                    .overlay(BarbellIcon())

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .lineLimit(1)
                    Text("\(trackingLabel) · \(exercise.sets.count) 组")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "6F6F76"))
                }

                Spacer()

                timerButton
                moreMenu
            }

            setsSection.padding(.top, 16)

            HStack(spacing: 0) {
                Button(action: onProgress) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 14, weight: .semibold))
                        Text("进度")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .frame(maxWidth: .infinity)
                }

                Rectangle()
                    .fill(Color(hex: "ECECEF"))
                    .frame(width: 1, height: 20)

                Button(action: onAddSet) {
                    HStack(spacing: 8) {
                        if isAddingSet {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                            Text("添加组")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .frame(maxWidth: .infinity)
                }
                .disabled(isAddingSet)
            }
            .frame(height: 48)
            .padding(.top, 18)
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.black.opacity(0.07), .black.opacity(0.025), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 18)
                .blur(radius: 4)
                .offset(y: -12)
                .allowsHitTesting(false)
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(hex: "EEEEF1"), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }

    @ViewBuilder
    private var setsSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("组").frame(width: 44)
                if exercise.showSecondColumn {
                    Text(ExerciseTrackingDisplay.secondColumnLabel(exercise.trackingType)).frame(maxWidth: .infinity)
                }
                Text(ExerciseTrackingDisplay.thirdColumnLabel(exercise.trackingType)).frame(maxWidth: .infinity)
                Spacer().frame(width: 44)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(hex: "8E8E93"))
            .multilineTextAlignment(.center)
            .padding(.bottom, 8)

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                VStack(spacing: 0) {
                    ActiveSetRow(
                        exercise: exercise,
                        set: set,
                        isSaving: savingSetIds.contains(set.sessionSetId),
                        onToggle: { onToggleSet(set.sessionSetId) },
                        onDelete: { onDeleteSet(set.sessionSetId) },
                        onUpdate: { w, r, d, dist in onUpdateSet(set.sessionSetId, w, r, d, dist) },
                        onFocusChange: { isEditing in onEditSet(isEditing ? set.sessionSetId : nil) }
                    )
                    .id("set-\(set.sessionSetId)")
                    if isRestVisible {
                        RestTimeChip(
                            set: set,
                            nextSet: nextSetForRest(set.sessionSetId),
                            isLatestCompletedRest: latestCompletedSetId == set.sessionSetId,
                            fallbackRestSeconds: exercise.restSeconds,
                            onRestDue: onRestDue
                        )
                        .padding(.top, 10)
                    }
                }
                if index < exercise.sets.count - 1 {
                    Spacer().frame(height: isRestVisible ? 10 : 9)
                }
            }
        }
    }

    private var trackingLabel: String {
        switch exercise.trackingType {
        case "weight_reps": return "杠铃"
        case "reps_only": return "自重"
        case "distance_time", "cardio": return "有氧器械"
        case "time_only": return "计时"
        default: return exercise.exerciseType
        }
    }

    private var timerButton: some View {
        Button(action: onToggleRest) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isRestVisible ? Color(hex: "1C1C1E") : Color.white)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "timer")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isRestVisible ? .white : Color(hex: "6F6F76"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isRestVisible ? Color(hex: "1C1C1E") : Color(hex: "ECECEF"), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private struct RestTimeChip: View {
        let set: FitnessSessionSet
        let nextSet: FitnessSessionSet?
        let isLatestCompletedRest: Bool
        let fallbackRestSeconds: Int
        let onRestDue: (FitnessSessionSet) -> Void

        var body: some View {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let state = restState(now: context.date)
                Text(state.text)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(state.isActive ? .white : Color(hex: "1C1C1E"))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(state.fillColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(state.strokeColor, lineWidth: 1)
                            )
                    )
                    .onChange(of: state.isDue) { _, isDue in
                        if isDue {
                            onRestDue(set)
                        }
                    }
                    .onAppear {
                        if state.isDue {
                            onRestDue(set)
                        }
                    }
            }
            .frame(maxWidth: .infinity)
        }

        private func restState(now: Date) -> RestState {
            let targetSeconds = set.restSeconds ?? fallbackRestSeconds
            guard set.isCompleted, let completedAt = set.completedAt else {
                return RestState(
                    text: Self.clockText(targetSeconds),
                    isActive: false,
                    isDue: false,
                    fillColor: Color.white.opacity(0.9),
                    strokeColor: Color(hex: "E5E5EA")
                )
            }

            let stopDate = nextSet?.timerStartedAt
            let isStopped = stopDate != nil || nextSet.map(Self.hasSetStarted) == true
            let elapsed = stopDate.map { max(0, Int($0.timeIntervalSince(completedAt))) }
                ?? (isStopped ? targetSeconds : max(0, Int(now.timeIntervalSince(completedAt))))
            let remaining = max(0, targetSeconds - elapsed)
            let isDue = !isStopped && isLatestCompletedRest && remaining == 0

            if isDue {
                return RestState(
                    text: "休息完成 00:00",
                    isActive: true,
                    isDue: true,
                    fillColor: Color(hex: "34C982"),
                    strokeColor: .clear
                )
            }

            return RestState(
                text: Self.clockText(remaining),
                isActive: !isStopped && isLatestCompletedRest,
                isDue: false,
                fillColor: (!isStopped && isLatestCompletedRest) ? Color(hex: "1C1C1E") : Color.white.opacity(0.9),
                strokeColor: (!isStopped && isLatestCompletedRest) ? .clear : Color(hex: "E5E5EA")
            )
        }

        private static func clockText(_ seconds: Int) -> String {
            let minutes = seconds / 60
            let secs = seconds % 60
            return String(format: "%02d:%02d", minutes, secs)
        }

        private static func hasSetStarted(_ set: FitnessSessionSet) -> Bool {
            set.timerStartedAt != nil
                || (set.timerAccumulatedSeconds ?? 0) > 0
                || set.timerStatus == "running"
                || set.timerStatus == "paused"
                || set.isCompleted
        }

        private struct RestState {
            let text: String
            let isActive: Bool
            let isDue: Bool
            let fillColor: Color
            let strokeColor: Color
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(role: .destructive, action: onDeleteExercise) {
                Label("删除动作", systemImage: "trash")
            }
        } label: {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .frame(width: 44, height: 44)
                .overlay(
                    Text("···")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .offset(y: -3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: "ECECEF"), lineWidth: 1)
                )
        }
    }
}

private struct ActiveSetRow: View {
    let exercise: FitnessSessionExercise
    let set: FitnessSessionSet
    let isSaving: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onUpdate: (Double?, Int?, Int?, Double?) -> Void
    let onFocusChange: (Bool) -> Void

    @State private var secondText: String
    @State private var thirdText: String
    @FocusState private var focused: ActiveSetField?
    @State private var dragOffset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var isTrackingDrag = false
    private let revealWidth: CGFloat = 72

    init(
        exercise: FitnessSessionExercise,
        set: FitnessSessionSet,
        isSaving: Bool,
        onToggle: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onUpdate: @escaping (Double?, Int?, Int?, Double?) -> Void,
        onFocusChange: @escaping (Bool) -> Void
    ) {
        self.exercise = exercise
        self.set = set
        self.isSaving = isSaving
        self.onToggle = onToggle
        self.onDelete = onDelete
        self.onUpdate = onUpdate
        self.onFocusChange = onFocusChange
        _secondText = State(initialValue: Self.initSecond(exercise: exercise, set: set))
        _thirdText = State(initialValue: Self.initThird(exercise: exercise, set: set))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { dragOffset = 0 }
                onDelete()
            }) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "F05B5B"))
                    .frame(width: 64, height: 40)
                    .overlay(
                        Image(systemName: "trash.fill")
                            .foregroundStyle(.white)
                            .font(.system(size: 16))
                    )
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Text("\(set.setOrder)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(set.isCompleted ? .white : Color(hex: "1C1C1E"))
                    .frame(width: 44, height: 40)
                    .background(
                        Circle()
                            .fill(set.isCompleted ? setNumberFill : .clear)
                            .frame(width: 34, height: 34)
                            .overlay(Circle().stroke(setNumberBorderColor, lineWidth: 1.5))
                    )

                if exercise.showSecondColumn {
                    setValueField(field: .second, keyboard: .decimalPad, text: $secondText)
                }

                setValueField(field: .third, keyboard: .numberPad, text: Binding(
                    get: { (exercise.isTimeBased && focused != .third) ? thirdDisplayText : thirdText },
                    set: { thirdText = $0 }
                ))

                Button(action: onToggle) {
                    Circle()
                        .fill(set.isCompleted ? completedGreen : .clear)
                        .overlay(Circle().stroke(set.isCompleted ? completedGreen : Color(hex: "D8D8DE"), lineWidth: 1.5))
                        .frame(width: 34, height: 34)
                        .frame(width: 44, height: 40)
                        .overlay(
                            Group {
                                if isSaving {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: statusSymbol)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(statusSymbolColor)
                                        .offset(x: statusSymbol == "play.fill" ? 2 : 0)
                                }
                            }
                        )
                }
                .disabled(isSaving)
            }
            .background(Color.white)
            .offset(x: dragOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        let horizontal = abs(value.translation.width)
                        let vertical = abs(value.translation.height)
                        guard horizontal > 28, horizontal > vertical * 1.7 else { return }
                        if !isTrackingDrag {
                            isTrackingDrag = true
                            dragStartOffset = dragOffset
                        }
                        dragOffset = min(0, max(-revealWidth, dragStartOffset + value.translation.width))
                    }
                    .onEnded { value in
                        isTrackingDrag = false
                        let horizontal = abs(value.translation.width)
                        let vertical = abs(value.translation.height)
                        guard horizontal > 28, horizontal > vertical * 1.7 else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
                            return
                        }
                        let projected = dragStartOffset + value.predictedEndTranslation.width
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = projected < -revealWidth / 2 ? -revealWidth : 0
                        }
                    }
            )
        }
        .clipped()
        .onChange(of: focused) { old, new in
            if old != nil && new == nil { commitUpdate() }
            onFocusChange(new != nil)
        }
        .onChange(of: set.actualWeightKg) { _, _ in
            if focused != .second { secondText = Self.initSecond(exercise: exercise, set: set) }
        }
        .onChange(of: set.actualDistanceMeters) { _, _ in
            if focused != .second { secondText = Self.initSecond(exercise: exercise, set: set) }
        }
        .onChange(of: set.actualReps) { _, _ in
            if focused != .third { thirdText = Self.initThird(exercise: exercise, set: set) }
        }
        .onChange(of: set.actualDurationSeconds) { _, _ in
            if focused != .third { thirdText = Self.initThird(exercise: exercise, set: set) }
        }
    }

    @ViewBuilder
    private func setValueField(
        field: ActiveSetField,
        keyboard: UIKeyboardType,
        text: Binding<String>
    ) -> some View {
        TextField("--", text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(fieldTextColor)
            .focused($focused, equals: field)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(focused == field ? Color(hex: "FFEDE3") : fieldFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(focused == field ? Color(hex: "FF7847") : fieldBorderColor, lineWidth: focused == field ? 2 : 1.5)
                    )
            )
            // While idle the field ignores touches, so a vertical drag scrolls the
            // list instead of being captured by the text field. A Button overlay
            // (which, unlike onTapGesture, lets ScrollView cancel it during a drag)
            // handles tap-to-edit. The TextField stays in the tree so focusing it
            // is reliable.
            .allowsHitTesting(focused == field)
            .overlay {
                if focused != field {
                    Button { focused = field } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
    }

    private func commitUpdate() {
        let isDistanceBased = ExerciseTrackingDisplay.isDistanceBased(exercise.trackingType)
        let weight: Double? = (exercise.showSecondColumn && !isDistanceBased) ? Double(secondText) : nil
        let distance: Double? = isDistanceBased ? Double(secondText) : nil
        let reps: Int? = exercise.isTimeBased ? nil : Int(thirdText)
        let duration: Int? = exercise.isTimeBased ? Int(thirdText) : nil
        onUpdate(weight, reps, duration, distance)
    }

    private static func initSecond(exercise: FitnessSessionExercise, set: FitnessSessionSet) -> String {
        if ExerciseTrackingDisplay.isDistanceBased(exercise.trackingType) {
            guard let d = set.actualDistanceMeters ?? set.plannedDistanceMeters else { return "" }
            return "\(Int(d))"
        }
        guard let w = set.actualWeightKg ?? set.plannedWeightKg else { return "" }
        return w == Double(Int(w)) ? "\(Int(w))" : String(format: "%.1f", w)
    }

    private static func initThird(exercise: FitnessSessionExercise, set: FitnessSessionSet) -> String {
        if exercise.isTimeBased {
            guard let d = set.actualDurationSeconds ?? set.plannedDurationSeconds else { return "" }
            return "\(d)"
        }
        guard let r = set.actualReps ?? set.plannedReps else { return "" }
        return "\(r)"
    }

    private var thirdDisplayText: String {
        guard exercise.isTimeBased, !thirdText.isEmpty, let secs = Int(thirdText) else { return thirdText }
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    private var isRunning: Bool { self.set.timerStatus == "running" }
    private var completedGreen: Color { Color(hex: "34C982") }
    private var completedFill: Color { Color(hex: "D8F4E8") }
    private var setNumberFill: Color { completedGreen }
    private var fieldFillColor: Color { self.set.isCompleted ? completedFill : .clear }
    private var fieldBorderColor: Color { self.set.isCompleted ? .clear : Color(hex: "D8D8DE") }
    private var fieldTextColor: Color { self.set.isCompleted ? completedGreen : Color(hex: "1C1C1E") }

    private var statusSymbol: String {
        if isRunning { return "pause.fill" }
        return set.isCompleted ? "checkmark" : "play.fill"
    }

    private var statusBorderColor: Color {
        if isRunning { return Color(hex: "FF7847") }
        return set.isCompleted ? completedGreen : Color(hex: "D8D8DE")
    }

    private var setNumberBorderColor: Color {
        if isRunning { return Color(hex: "FF7847") }
        return set.isCompleted ? completedGreen : Color(hex: "D8D8DE")
    }

    private var statusSymbolColor: Color {
        if set.isCompleted { return .white }
        return isRunning ? Color(hex: "FF7847") : Color(hex: "1C1C1E")
    }
}

private enum ActiveSetField: Hashable { case second, third }

private struct ActiveExerciseConnector: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(hex: "E7E7EC"))
                .frame(height: 1)
            Circle()
                .fill(Color.white)
                .frame(width: 52, height: 52)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                .overlay(
                    Image(systemName: "link")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(hex: "8E8E93"))
                )
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Template Grid Card

private struct TemplateGridCard: View {
    let template: FitnessTemplateSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(template.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

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
    }

    private var volumeDigits: [(offset: Int, element: String)] {
        let str = template.estimatedVolumeKg > 0 ? String(Int(template.estimatedVolumeKg)) : "0"
        return Array(str.enumerated()).map { (offset: $0.offset, element: String($0.element)) }
    }
}

// MARK: - Template Info Sheet (新建 & 修改 复用)

struct TemplateInfoSheet: View {
    let title: String
    let confirmLabel: String
    let initialName: String
    let initialTheme: String
    let onSave: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var trainingTheme: String
    @FocusState private var nameFocused: Bool

    init(title: String, confirmLabel: String, initialName: String, initialTheme: String,
         onSave: @escaping (String, String?) -> Void) {
        self.title = title
        self.confirmLabel = confirmLabel
        self.initialName = initialName
        self.initialTheme = initialTheme
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _trainingTheme = State(initialValue: initialTheme)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("模板名称（必填）", text: $name)
                        .focused($nameFocused)
                    TextField("训练主题，如：下半身、推胸", text: $trainingTheme)
                } footer: {
                    if title == "新建模板" {
                        Text("保存后可在模板详情中添加锻炼动作。")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Text(confirmLabel).fontWeight(.semibold)
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear { nameFocused = true }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        let trimName = name.trimmingCharacters(in: .whitespaces)
        guard !trimName.isEmpty else { return }
        let theme: String? = trainingTheme.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : trainingTheme.trimmingCharacters(in: .whitespaces)
        onSave(trimName, theme)
        dismiss()
    }
}

// MARK: - Workout Rating Sheet

private struct RPELevel {
    let label: String
    let description: String
}

private let rpeLevels: [RPELevel] = [
    RPELevel(label: "极轻松", description: "几乎不费力，如悠闲散步。"),
    RPELevel(label: "很轻松", description: "轻微费力，可以轻松唱歌。"),
    RPELevel(label: "轻松",   description: "稍有费力，可以轻松交谈。"),
    RPELevel(label: "稍费力", description: "有点费力，仍可正常对话。"),
    RPELevel(label: "疲倦",   description: "用力；呼吸沉重，说话困难。"),
    RPELevel(label: "吃力",   description: "相当费力，只能说短词。"),
    RPELevel(label: "很吃力", description: "非常用力，难以说话。"),
    RPELevel(label: "非常吃力", description: "呼吸急促，难以维持节奏。"),
    RPELevel(label: "极度吃力", description: "接近极限，几乎无法说话。"),
    RPELevel(label: "精疲力竭", description: "已达极限，无法继续。"),
]

struct WorkoutRatingSheet: View {
    @Binding var rpe: Double
    let onSave: () -> Void

    private var level: RPELevel { rpeLevels[max(0, min(9, Int(rpe.rounded()) - 1)) ] }

    private var labelColor: Color {
        if rpe <= 3 { return Color(hex: "5E8FFF") }
        if rpe <= 6 { return Color(hex: "FF9F0A") }
        return Color(hex: "FF453A")
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("体能训练怎么样?")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .padding(.bottom, 36)

            ArcRPESlider(value: $rpe)
                .frame(width: 340, height: 320)

            VStack(spacing: 6) {
                Text(level.label)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(labelColor)
                Text(level.description)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "8E8E93"))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            Spacer()

            Button(action: onSave) {
                Text("保存并结束体能训练")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color(hex: "1C1C1E"), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color(hex: "F2F2F7").ignoresSafeArea())
    }
}

struct ArcRPESlider: View {
    @Binding var value: Double

    private let startDeg: Double = 135
    private let sweepDeg: Double = 270
    private let trackWidth: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2 + 10)
            let radius = min(size.width, size.height) / 2 - trackWidth - 8

            ZStack {
                // Background track
                arcPath(center: center, radius: radius, from: startDeg, sweep: sweepDeg)
                    .stroke(Color(hex: "E5E5EA"), style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))

                // Active gradient track
                let activeSweep = (value - 1) / 9 * sweepDeg
                if activeSweep > 0 {
                    arcPath(center: center, radius: radius, from: startDeg, sweep: max(activeSweep, 2))
                        .stroke(
                            AngularGradient(
                                colors: [Color(hex: "8AABFF"), Color(hex: "A78BFF"), Color(hex: "FFCA6B"), Color(hex: "FF9F0A")],
                                center: .center,
                                startAngle: .degrees(startDeg),
                                endAngle: .degrees(startDeg + sweepDeg)
                            ),
                            style: StrokeStyle(lineWidth: trackWidth, lineCap: .round)
                        )
                }

                // Tick dots
                ForEach(1...10, id: \.self) { i in
                    let pos = pointOnArc(center: center, radius: radius, for: Double(i))
                    Circle()
                        .fill(Double(i) <= value.rounded() ? Color.white.opacity(0.65) : Color(hex: "C7C7CC"))
                        .frame(width: 6, height: 6)
                        .position(pos)
                }

                // Handle
                let hp = pointOnArc(center: center, radius: radius, for: value)
                let handleColor = self.handleColor
                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(handleColor, lineWidth: 3.5))
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                    .position(hp)

                // Center value
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 76, weight: .heavy, design: .rounded))
                    .foregroundStyle(handleColor)
                    .position(x: center.x, y: center.y - 8)

                // "1" and "10" labels
                let p1 = pointOnArc(center: center, radius: radius + trackWidth + 10, for: 1)
                let p10 = pointOnArc(center: center, radius: radius + trackWidth + 10, for: 10)
                Text("1")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "8E8E93"))
                    .position(x: p1.x - 4, y: p1.y + 4)
                Text("10")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "8E8E93"))
                    .position(x: p10.x + 4, y: p10.y + 4)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 + 10)
                        updateValue(from: drag.location, center: center)
                    }
            )
        }
    }

    private func arcPath(center: CGPoint, radius: CGFloat, from: Double, sweep: Double) -> Path {
        Path { path in
            path.addArc(center: center, radius: radius,
                        startAngle: .degrees(from),
                        endAngle: .degrees(from + sweep),
                        clockwise: false)
        }
    }

    private func pointOnArc(center: CGPoint, radius: CGFloat, for v: Double) -> CGPoint {
        let deg = startDeg + (v - 1) / 9 * sweepDeg
        let rad = deg * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(cos(rad)), y: center.y + radius * CGFloat(sin(rad)))
    }

    private func updateValue(from point: CGPoint, center: CGPoint) {
        let dx = point.x - center.x
        let dy = point.y - center.y
        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 { angle += 360 }

        // Map angle into arc range [startDeg, startDeg+sweepDeg]
        var normalized = angle - startDeg
        if normalized < 0 { normalized += 360 }
        // Treat angles just past the end (in the gap) as clamped
        let fraction = max(0, min(1, normalized / sweepDeg))
        // Snap to integer values
        let raw = fraction * 9 + 1
        value = (raw).rounded().clamped(to: 1...10)
    }

    private var handleColor: Color {
        if value <= 3 { return Color(hex: "8AABFF") }
        if value <= 6 { return Color(hex: "FF9F0A") }
        return Color(hex: "FF453A")
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
