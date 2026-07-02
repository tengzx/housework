import SwiftUI
import Combine
import UIKit
import AudioToolbox


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
            Button("好") { Haptics.tap(); vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .alert("还有未完成的组", isPresented: $showIncompleteAlert) {
            Button("继续训练", role: .cancel) { Haptics.tap() }
            Button("仍然完成", role: .destructive) { Haptics.tap(); showRatingSheet = true }
        } message: {
            Text("还有 \(vm.incompleteSetCount) 组未完成，确定要结束训练吗？")
        }
        .alert("删除本次训练？", isPresented: $showDiscardConfirm) {
            Button("取消", role: .cancel) { Haptics.tap() }
            Button("删除训练", role: .destructive) {
                Haptics.tap()
                Task {
                    if await vm.discard() {
                        await onCompleted()
                        dismiss()
                    }
                }
            }
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
        .buttonStyle(HapticButtonStyle())
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
                Haptics.tap()
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
                    Haptics.tap()
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
                    Haptics.tap()
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
                    Haptics.tap()
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
                Button {
                    Haptics.tap()
                    onProgress()
                } label: {
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

                Button {
                    Haptics.tap()
                    onAddSet()
                } label: {
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
                Rectangle()
                    .fill(Color(hex: "EEEEF1"))
                    .frame(height: 1)
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
        .buttonStyle(HapticButtonStyle())
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
            Button(role: .destructive) {
                Haptics.tap()
                onDeleteExercise()
            } label: {
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
            .buttonStyle(HapticButtonStyle())

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

                Button {
                    Haptics.tap()
                    onToggle()
                } label: {
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
                    .buttonStyle(HapticButtonStyle())
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
