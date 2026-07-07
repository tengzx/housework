import SwiftUI
import Combine
import UIKit
import AudioToolbox
import UserNotifications


struct FitnessActiveSessionView: View {
    let onCompleted: () async -> Void

    @ObservedObject private var vm: FitnessActiveSessionViewModel
    @EnvironmentObject private var workout: ActiveWorkoutStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var restVisibleExerciseIds: Set<Int> = []
    @State private var remindedRestSetIds: Set<Int> = []
    @State private var showDiscardConfirm = false
    @State private var showExerciseLibrary = false
    @State private var progressTarget: ExerciseProgressTarget?
    @State private var detailTarget: FitnessExercise?
    @State private var showRatingSheet = false
    @State private var ratingValue: Double = 5
    @State private var showIncompleteAlert = false
    @State private var editingSetId: Int?

    init(vm: FitnessActiveSessionViewModel, onCompleted: @escaping () async -> Void) {
        self.onCompleted = onCompleted
        self.vm = vm
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.white.ignoresSafeArea()

            ScrollViewReader { proxy in
                List {
                    Section {
                        activeHeader
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 2, trailing: 20))
                    }

                    if vm.isLoading && vm.detail == nil {
                        Section {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 32)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    } else if let detail = vm.detail {
                        let contexts = orderedSetContexts(from: detail)
                        let latestCompletedSetId = contexts
                            .filter { $0.set.isCompleted }
                            .max { ($0.set.completedAt ?? .distantPast) < ($1.set.completedAt ?? .distantPast) }?
                            .set.sessionSetId
                        Section {
                            ForEach(detail.exercises, id: \.id) { exercise in
                                exerciseSection(
                                    exercise: exercise,
                                    latestCompletedSetId: latestCompletedSetId,
                                    contexts: contexts
                                )
                                .listRowInsets(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                            .onMove { source, destination in
                                Haptics.tap()
                                Task { await vm.moveExercise(from: source, to: destination) }
                            }
                        }

                        Section {
                            addExerciseButton
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 0, trailing: 16))
                        }
                    } else if let errorMessage = vm.errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color(hex: "F05B5B"))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 32)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }

                    // Bottom spacer so the floating mini player never covers content
                    Section {
                        Color.clear
                            .frame(height: 118)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                    }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(12)
                .contentMargins(.top, 4, for: .scrollContent)
                .scrollContentBackground(.hidden)
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
                // Select all text when a field begins editing so the user can type a
                // new value straight away instead of clearing the old one first.
                .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { notification in
                    guard let textField = notification.object as? UITextField else { return }
                    DispatchQueue.main.async {
                        textField.selectAll(nil)
                    }
                }
                // Pull the list past its top and keep dragging down to collapse the
                // workout into the floating bar (sheet-style overscroll dismiss).
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    // How far the content is pulled below its top; positive on overscroll.
                    -(geometry.contentOffset.y + geometry.contentInsets.top)
                } action: { _, overscroll in
                    if overscroll > 90 && !workout.isMinimized {
                        Haptics.tap()
                        workout.minimize()
                    }
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
        .task { await RestReminderNotifier.requestAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Back in the app — the in-app countdown/sound takes over, so
                // clear any pending or already-delivered rest notification.
                RestReminderNotifier.cancel()
            case .background, .inactive:
                // Leaving the app mid-rest: schedule a local notification for the
                // moment rest ends so the alert/sound fires while backgrounded.
                if let rest = currentRestEnd(now: Date()), rest.date > Date() {
                    RestReminderNotifier.schedule(at: rest.date, exerciseName: rest.exerciseName)
                } else {
                    RestReminderNotifier.cancel()
                }
            @unknown default:
                break
            }
        }
        .sheet(isPresented: $showExerciseLibrary) {
            FitnessExerciseLibrarySheet(
                preselected: (vm.detail?.exercises ?? []).map {
                    FitnessExercise.lightweight(
                        id: $0.exerciseId,
                        name: $0.name,
                        trackingType: $0.trackingType
                    )
                }
            ) { selected in
                Task { await vm.addExercisesToSession(selected) }
            }
        }
        .sheet(item: $progressTarget) { target in
            ExerciseProgressSheet(target: target)
        }
        .sheet(item: $detailTarget) { exercise in
            FitnessExerciseDetailSheet(exercise: exercise)
        }
        .fullScreenCover(isPresented: $showRatingSheet) {
            WorkoutRatingSheet(
                rpe: $ratingValue,
                canUpdateTemplate: vm.detail?.templateId != nil,
                onSave: {
                    // Keep the rating cover up during the save. On success, pop the
                    // active session directly (the cover tears down with it) so we go
                    // straight to home without flashing the training screen. Only
                    // close the cover on failure, to reveal the error alert.
                    Task {
                        if await vm.complete(rpe: ratingValue) {
                            await onCompleted()
                            workout.end()
                        } else {
                            showRatingSheet = false
                        }
                    }
                },
                onSaveAndUpdateTemplate: {
                    Task {
                        if await vm.completeAndUpdateTemplate(rpe: ratingValue) {
                            await onCompleted()
                            workout.end()
                        } else {
                            showRatingSheet = false
                        }
                    }
                }
            )
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
                        workout.end()
                    }
                }
            }
        } message: {
            Text("删除后不会保存为完成记录。")
        }
    }

    private func exerciseSection(
        exercise: FitnessSessionExercise,
        latestCompletedSetId: Int?,
        contexts: [(exercise: FitnessSessionExercise, set: FitnessSessionSet)]
    ) -> some View {
        let exId = exercise.sessionExerciseId
        return ActiveExerciseCard(
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
            onOpenDetail: {
                detailTarget = FitnessExercise.lightweight(
                    id: exercise.exerciseId,
                    name: exercise.name,
                    trackingType: exercise.trackingType
                )
            },
            onToggleSet: { setId in Task { await vm.toggleSetCompletion(exerciseId: exId, setId: setId) } },
            onAddSet: { Task { await vm.addSet(to: exId) } },
            onDeleteExercise: { Task { await vm.deleteExerciseFromSession(exerciseId: exId) } },
            onDeleteSet: { setId in Task { await vm.deleteSetFromSession(exerciseId: exId, setId: setId) } },
            onUpdateSet: { setId, w, r, d, dist in Task { await vm.updateSetValues(exerciseId: exId, setId: setId, actualWeightKg: w, actualReps: r, actualDurationSeconds: d, actualDistanceMeters: dist) } },
            onRestDue: { set in playRestReminder(for: set.sessionSetId) },
            onEditSet: { setId in editingSetId = setId }
        )
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
            .buttonStyle(.borderless)
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
            let state = vm.miniPlayerState(now: context.date)
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

                Button {
                    Haptics.tap()
                    workout.minimize()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: "8E8E93"))
                        .frame(width: 30, height: 44)
                }
                .buttonStyle(.borderless)

                // Live heart rate from the watch — same source the collapsed
                // floating bar uses. Falls back to a dim placeholder heart when
                // no reading has arrived yet, so the layout stays stable.
                if let bpm = workout.remoteHeartRate {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.red)
                        Text("\(bpm)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .transition(.opacity)
                } else {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: "A8A8AD"))
                }

                Button {
                    Haptics.tap()
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    if state.isFinishAction {
                        // All sets done: finish the workout straight from here.
                        if vm.isCompleting { return }
                        if vm.incompleteSetCount > 0 {
                            showIncompleteAlert = true
                        } else {
                            showRatingSheet = true
                        }
                    } else {
                        Task { await vm.handleMiniPlayerAction() }
                    }
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

    /// The wall-clock moment the currently-running rest countdown ends, plus the
    /// name of the exercise whose set is up next. Nil when no rest is pending
    /// (session paused, a set is actively running, everything done, or the next
    /// set already started). Mirrors the rest branch of `miniPlayerState`.
    private func currentRestEnd(now: Date) -> (date: Date, exerciseName: String)? {
        guard let detail = vm.detail, !vm.isSessionPaused else { return nil }
        let contexts = orderedSetContexts(from: detail)
        if contexts.contains(where: { $0.set.timerStatus == "running" }) { return nil }
        let lastCompleted = contexts
            .filter { $0.set.isCompleted }
            .max { ($0.set.completedAt ?? .distantPast) < ($1.set.completedAt ?? .distantPast) }
        guard let lastCompleted,
              let completedAt = lastCompleted.set.completedAt,
              let next = fitnessNextTargetContext(in: contexts),
              !hasSetStarted(next.set) else { return nil }
        let restSeconds = lastCompleted.set.restSeconds ?? lastCompleted.exercise.restSeconds
        return (completedAt.addingTimeInterval(TimeInterval(restSeconds)), next.exercise.name)
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

}

private struct ActiveExerciseCard: View {
    let exercise: FitnessSessionExercise
    let savingSetIds: Set<Int>
    let isAddingSet: Bool
    let isRestVisible: Bool
    let latestCompletedSetId: Int?
    let nextSetForRest: (Int) -> FitnessSessionSet?
    let onToggleRest: () -> Void
    let onProgress: () -> Void
    let onOpenDetail: () -> Void
    let onToggleSet: (Int) -> Void
    let onAddSet: () -> Void
    let onDeleteExercise: () -> Void
    let onDeleteSet: (Int) -> Void
    let onUpdateSet: (Int, Double?, Int?, Int?, Double?) -> Void
    let onRestDue: (FitnessSessionSet) -> Void
    let onEditSet: (Int?) -> Void

    @State private var isDeletingSets = false

    var body: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 8)

            columnHeaderRow
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ForEach(exercise.sets, id: \.id) { set in
                VStack(spacing: 0) {
                    ActiveSetRow(
                        exercise: exercise,
                        set: set,
                        isSaving: savingSetIds.contains(set.sessionSetId),
                        onToggle: { onToggleSet(set.sessionSetId) },
                        onUpdate: { w, r, d, dist in onUpdateSet(set.sessionSetId, w, r, d, dist) },
                        onFocusChange: { isEditing in onEditSet(isEditing ? set.sessionSetId : nil) },
                        showDelete: isDeletingSets,
                        onDelete: { onDeleteSet(set.sessionSetId) }
                    )
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
                .id("set-\(set.sessionSetId)")
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }

            footerRow
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .exerciseCardBackground()
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(urlString: exercise.imageUrl, size: 54, cornerRadius: 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture { Haptics.tap(); onOpenDetail() }
                Text("\(trackingLabel) · \(exercise.sets.count) 组")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "9A9AA0"))
            }

            Spacer()

            timerButton
            moreMenu
        }
    }

    private var columnHeaderRow: some View {
        HStack(spacing: 10) {
            Text("组").frame(width: 44)
            if exercise.showSecondColumn {
                Text(ExerciseTrackingDisplay.secondColumnLabel(exercise.trackingType)).frame(maxWidth: .infinity)
            }
            Text(ExerciseTrackingDisplay.thirdColumnLabel(exercise.trackingType)).frame(maxWidth: .infinity)
            Spacer().frame(width: isDeletingSets ? 84 : 44)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color(hex: "8E8E93"))
        .multilineTextAlignment(.center)
    }

    private var footerRow: some View {
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
            .buttonStyle(.borderless)

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
            .buttonStyle(.borderless)
            .disabled(isAddingSet)
        }
        .frame(height: 44)
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

            Button {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.2)) { isDeletingSets.toggle() }
            } label: {
                Label(isDeletingSets ? "完成删除组" : "删除组",
                      systemImage: isDeletingSets ? "checkmark" : "minus.circle")
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
    let onUpdate: (Double?, Int?, Int?, Double?) -> Void
    let onFocusChange: (Bool) -> Void
    let showDelete: Bool
    let onDelete: () -> Void

    @State private var secondText: String
    @State private var thirdText: String
    @FocusState private var focused: ActiveSetField?

    init(
        exercise: FitnessSessionExercise,
        set: FitnessSessionSet,
        isSaving: Bool,
        onToggle: @escaping () -> Void,
        onUpdate: @escaping (Double?, Int?, Int?, Double?) -> Void,
        onFocusChange: @escaping (Bool) -> Void,
        showDelete: Bool,
        onDelete: @escaping () -> Void
    ) {
        self.exercise = exercise
        self.set = set
        self.isSaving = isSaving
        self.onToggle = onToggle
        self.onUpdate = onUpdate
        self.onFocusChange = onFocusChange
        self.showDelete = showDelete
        self.onDelete = onDelete
        _secondText = State(initialValue: Self.initSecond(exercise: exercise, set: set))
        _thirdText = State(initialValue: Self.initThird(exercise: exercise, set: set))
    }

    var body: some View {
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
            .buttonStyle(.borderless)
            .disabled(isSaving)

            if showDelete {
                Button {
                    Haptics.tap()
                    onDelete()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(hex: "F05B5B"))
                        .frame(width: 30, height: 40)
                }
                .buttonStyle(.borderless)
                .transition(.scale.combined(with: .opacity))
            }
        }
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

/// Schedules a single local notification so the "rest finished" alert and sound
/// fire even when the app is backgrounded (the in-app timer/sound only runs while
/// the app is active).
private enum RestReminderNotifier {
    private static let identifier = "fitness.rest.reminder"

    /// Ask for alert + sound permission. Safe to call repeatedly; the system only
    /// prompts once and returns the stored decision afterwards.
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// Schedule the reminder to fire at `date`. Replaces any previously scheduled
    /// one so only the latest rest period is pending.
    static func schedule(at date: Date, exerciseName: String?) {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "休息结束"
        content.body = exerciseName.map { "开始下一组：\($0)" } ?? "开始下一组"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.add(request)
    }

    /// Remove any pending and already-delivered rest reminder.
    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
