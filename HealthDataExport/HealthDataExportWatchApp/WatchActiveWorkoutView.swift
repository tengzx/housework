import SwiftUI

/// The live workout screen: one swipeable page per set. Each page shows the
/// target (or logged) weight/reps, live heart rate, and a start/complete button.
/// Completing a set opens the editor to log the real numbers; finishing all sets
/// reveals the rating page which submits the session.
struct WatchActiveWorkoutView: View {
    let sessionId: Int
    let name: String
    let playsStartCountdown: Bool

    @StateObject private var vm: WatchWorkoutViewModel
    // Shared singleton, not a view-owned @StateObject: the HK session must
    // outlive this view so the async finishWorkout can complete even when the
    // view is torn down (on completion, or when the phone ends the workout).
    @ObservedObject private var workout = WatchWorkoutManager.shared
    @ObservedObject private var activeStore = WatchActiveWorkoutStore.shared
    @ObservedObject private var onset = SetOnsetDetector.shared

    /// Selected page: a set's `sessionSetId`, a per-set controls tag, or `finishTag`.
    @State private var selection: Int = 0
    @State private var editingSetId: Int?
    @State private var showRating = false
    @State private var rpe: Double = 7
    @State private var didAutoAdvance = false
    @State private var showDiscardConfirm = false
    /// The Apple-Workout-style "3·2·1" pre-roll; nil once it finishes. `didCountdown`
    /// guards against re-running it when the view reappears mid-session. Seeded to
    /// `3` on a fresh start so the opaque overlay masks the very first frame — the
    /// session detail then loads *behind* the countdown, leaving no black gap.
    @State private var countdown: Int?
    @State private var didCountdown = false
    /// While true the set pages stay hidden so the "3·2·1" pre-roll shows on a
    /// clean screen first, rather than flashing the first set behind it.
    @State private var isPreparing = true
    /// Guards the one-time start sequence. On watchOS presenting a sheet makes
    /// this view disappear/reappear, which re-fires `.task` — without this the
    /// workout session (and countdown) would restart on every sheet dismiss.
    @State private var didBegin = false
    /// Set the detector just auto-started (no confirm tap). Drives the transient
    /// "已开始 · 撤销" banner; nil when nothing to undo.
    @State private var autoStarted: OnsetSuggestion?

    private static let finishTag = -1
    private static func controlsTag(for setId: Int) -> Int { -1_000_000 - setId }
    private static func isControlsTag(_ tag: Int) -> Bool { tag <= -1_000_000 }

    init(sessionId: Int, name: String, playsStartCountdown: Bool = false) {
        self.sessionId = sessionId
        self.name = name
        self.playsStartCountdown = playsStartCountdown
        _vm = StateObject(wrappedValue: WatchWorkoutViewModel(sessionId: sessionId, name: name))
        // Seed the countdown so the opaque overlay is on screen from frame one.
        _countdown = State(initialValue: playsStartCountdown ? 3 : nil)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(
                    colors: isPreparing ? [WK.bg, WK.bg] : currentPageTint,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .task {
                guard !didBegin else { return }
                didBegin = true
                workout.start(sessionId: sessionId)
                if playsStartCountdown {
                    // Load the session detail *behind* the pre-roll: the opaque
                    // countdown is already on screen (seeded in init), so the
                    // network latency is fully masked — no black gap after it.
                    async let loaded: Void = vm.load()
                    await runStartCountdown()
                    await loaded
                } else {
                    // Resumed session: no pre-roll, just load.
                    await vm.load()
                }
                if let first = vm.nextTarget ?? vm.orderedContexts.first {
                    selection = first.id
                }
                withAnimation(.easeOut(duration: 0.2)) { countdown = nil }
                isPreparing = false
                await autoStartFirstSetIfFresh()
            }
            .onDisappear {
                // End (and save) the HK session on a real teardown — e.g. the
                // workout was ended from the phone. Skip when a sheet/dialog is
                // up: on watchOS presenting a sheet also fires onDisappear, and
                // that must NOT end the still-running workout. Completing/
                // discarding already end the session explicitly before this,
                // and end() is safe to call again (no-op).
                if editingSetId == nil && !showRating && !showDiscardConfirm {
                    workout.end()
                }
                onset.disarm()
            }
            .onChange(of: armTarget, initial: true) { _, target in
                if let target { onset.arm(target) } else { onset.disarm() }
            }
            .onChange(of: activeStore.reloadTick) { _, _ in
                Task {
                    await vm.load()
                    advanceAfterRemoteUpdate()
                }
            }
            .onChange(of: activeStore.snapshotTick) { _, _ in
                if let snapshot = activeStore.latestSnapshot {
                    vm.applyRemoteSnapshot(snapshot)
                    advanceAfterRemoteUpdate()
                }
            }
            .onChange(of: workout.heartRate) { _, bpm in
                if bpm > 0 {
                    WatchAuthSync.shared.broadcastHeartRate(bpm, sessionId: sessionId)
                    WorkoutSessionRecorder.shared.logHeartRate(bpm)
                }
            }
            .onChange(of: onset.suggestion) { _, s in
                guard let s else { return }
                // Auto-start on detection — no confirm tap. The transient undo
                // banner below is the safety net for the rare false positive.
                WorkoutSessionRecorder.shared.logSuggest(setId: s.setId)
                WorkoutSessionRecorder.shared.logConfirm(setId: s.setId)
                onset.disarm()
                Task { await vm.startSet(s.setId) }
                withAnimation(.easeOut(duration: 0.2)) { autoStarted = s }
            }
            .sheet(item: editingContext) { context in
                WatchSetEditorView(
                    context: context,
                    isSaving: vm.isBusy(context.set.sessionSetId),
                    onSave: { weight, reps, duration, distance in
                        Task {
                            await vm.completeSet(
                                setId: context.set.sessionSetId,
                                actualWeightKg: weight,
                                actualReps: reps,
                                actualDurationSeconds: duration,
                                actualDistanceMeters: distance
                            )
                            Haptics.notify(success: true)
                            editingSetId = nil
                            advanceAfterCompletion()
                        }
                    },
                    onDelete: {
                        Task {
                            await vm.deleteSet(context.set.sessionSetId)
                            editingSetId = nil
                        }
                    }
                )
            }
            .sheet(isPresented: $showRating) {
                WatchRatingView(rpe: $rpe, isSubmitting: vm.isCompleting) {
                    Task {
                        if await vm.complete(rpe: rpe) {
                            Haptics.notify(success: true)
                            showRating = false
                            workout.end()
                            WatchActiveWorkoutStore.shared.endLocal()
                        }
                    }
                }
            }
            .confirmationDialog(SharedL10n.tr("watch.fitness.delete_workout_confirm"), isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                Button(SharedL10n.tr("common.delete"), role: .destructive) {
                    Task {
                        if await vm.discard() {
                            workout.discard()
                            // Belt-and-suspenders: remove any HKWorkout already
                            // saved for this session (normally none, since discard
                            // never finishes the builder).
                            await WatchWorkoutManager.deleteWorkout(sessionId: sessionId)
                            Haptics.notify(success: true)
                            WatchActiveWorkoutStore.shared.endLocal()
                        }
                    }
                }
                Button(SharedL10n.tr("common.cancel"), role: .cancel) {}
            }
            .overlay {
                if let countdown {
                    CountdownOverlay(value: countdown)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if let started = autoStarted {
                    OnsetAutoStartBanner(
                        suggestion: started,
                        onUndo: {
                            WorkoutSessionRecorder.shared.logIgnore(setId: started.setId)
                            onset.dismissSuggestion()   // 15s cooldown so it won't instantly re-fire
                            Task { await vm.reopenSet(started.setId) }
                            withAnimation(.easeOut(duration: 0.2)) { autoStarted = nil }
                        },
                        onDismiss: {
                            withAnimation(.easeOut(duration: 0.2)) { autoStarted = nil }
                        }
                    )
                    .id(started.setId)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: autoStarted)
    }

    /// Play the "3·2·1" pre-roll. It's already on screen (seeded in init) so the
    /// session detail loads behind it; this just animates the ticks. The caller
    /// clears the countdown and auto-starts the first set once loading finishes.
    private func runStartCountdown() async {
        guard !didCountdown else { return }
        didCountdown = true
        for value in stride(from: 3, through: 1, by: -1) {
            withAnimation(.easeOut(duration: 0.2)) { countdown = value }
            Haptics.tap()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func autoStartFirstSetIfFresh() async {
        let contexts = vm.orderedContexts
        guard !contexts.isEmpty,
              contexts.allSatisfy({ !$0.set.isCompleted && $0.set.timerStatus != "running" }),
              let first = vm.nextTarget ?? vm.orderedContexts.first else { return }
        selection = first.id
        withAnimation(.easeOut(duration: 0.2)) { isPreparing = false }
        if let first = vm.nextTarget ?? vm.orderedContexts.first {
            await vm.startSet(first.id)
            Haptics.notify(success: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.orderedContexts.isEmpty {
            // Loading, or the brief pre-roll before data arrives. Any playing
            // countdown draws its own opaque canvas on top of this.
            if isPreparing || vm.isLoading {
                ProgressView().tint(.white)
            } else {
                Text(vm.errorMessage ?? SharedL10n.tr("watch.fitness.no_exercises"))
                    .font(.system(size: 13))
                    .foregroundStyle(WK.muted)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        } else {
            // Mount the TabView as soon as data exists — into the already
            // full-size container — so the first `.page` lays out at full
            // height instead of being measured mid-transition (which left
            // the first set not filling the screen). The countdown overlay,
            // being opaque, hides this while a pre-roll is still playing.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                // Rest remaining for the set we're about to do; `nil` once rest
                // is over. Tracked here so the falling edge (→ nil) can buzz.
                let restNow = vm.nextTarget.flatMap { vm.restRemaining(for: $0, now: timeline.date) }
                TabView(selection: $selection) {
                    ForEach(vm.orderedContexts) { context in
                        SetPageView(
                            context: context,
                            heartRate: workout.heartRate,
                            now: timeline.date,
                            restRemaining: vm.restRemaining(for: context, now: timeline.date),
                            isBusy: vm.isBusy(context.set.sessionSetId),
                            onStart: { Task { await vm.startSet(context.set.sessionSetId) } },
                            onComplete: { editingSetId = context.set.sessionSetId },
                            onReopen: { Task { await vm.reopenSet(context.set.sessionSetId) } }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(context.set.sessionSetId)

                        ControlsPageView(
                            elapsed: Int(timeline.date.timeIntervalSince(vm.detail?.startedAt ?? timeline.date)),
                            activeKcal: workout.activeEnergyKcal,
                            heartRate: workout.heartRate,
                            isPaused: workout.isPaused,
                            onEnd: { showRating = true },
                            onPauseToggle: { workout.isPaused ? workout.resume() : workout.pause() },
                            onDelete: { showDiscardConfirm = true }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(Self.controlsTag(for: context.set.sessionSetId))
                    }

                    if vm.isFinished {
                        FinishPageView(
                            elapsed: Int(timeline.date.timeIntervalSince(vm.detail?.startedAt ?? timeline.date)),
                            volume: vm.detail?.totalVolumeKg ?? 0,
                            sets: vm.completedCount
                        ) {
                            showRating = true
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(Self.finishTag)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: vm.isFinished) { _, finished in
                    if finished && !didAutoAdvance {
                        didAutoAdvance = true
                        selection = Self.finishTag
                    }
                }
                .onChange(of: restNow) { old, new in
                    // Rest timer expired: it counted down to the end and cleared.
                    // Buzz so the wrist notices even when the screen is asleep.
                    // Guard on a small `old` so manually starting the next set
                    // early (which also clears rest, but from a larger value)
                    // doesn't fire the buzz.
                    if let old, old <= 2, new == nil {
                        Haptics.notify(success: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(
                    colors: currentPageTint,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }

    private var currentPageTint: [Color] {
        if selection == Self.finishTag {
            return [Color(hex: "1B4B36"), Color(hex: "0B2B1E")]
        }
        if Self.isControlsTag(selection) {
            return [WK.bg, WK.bg]
        }
        guard let context = vm.orderedContexts.first(where: { $0.id == selection }) ?? vm.nextTarget ?? vm.orderedContexts.first else {
            return [WK.bg, WK.bg]
        }
        if context.set.isCompleted { return [Color(hex: "1B4B36"), Color(hex: "0B2B1E")] }
        if context.set.timerStatus == "running" { return [Color(hex: "7A1F3D"), Color(hex: "3A0E1E")] }
        return [Color(hex: "1E3A6B"), Color(hex: "0B1B36")]
    }

    /// The set the onset detector should watch for: the next pending set, but
    /// only when nothing else is going on (no set running, no sheet/dialog/pre-roll).
    /// `nil` disarms the detector.
    private var armTarget: OnsetSuggestion? {
        guard !isPreparing, countdown == nil, editingSetId == nil,
              !showRating, !showDiscardConfirm,
              vm.runningContext == nil, let next = vm.nextTarget else { return nil }
        return OnsetSuggestion(
            setId: next.set.sessionSetId,
            exerciseName: next.exercise.name,
            setIndex: next.exerciseSetIndex,
            setCount: next.exerciseSetCount
        )
    }

    private var editingContext: Binding<WatchWorkoutViewModel.SetContext?> {
        Binding(
            get: { vm.orderedContexts.first { $0.set.sessionSetId == editingSetId } },
            set: { editingSetId = $0?.set.sessionSetId }
        )
    }

    private func advanceAfterCompletion() {
        if vm.isFinished {
            selection = Self.finishTag
        } else if let next = vm.nextTarget {
            selection = next.id
        }
    }

    private func advanceAfterRemoteUpdate() {
        guard !Self.isControlsTag(selection) else { return }
        if vm.isFinished {
            selection = Self.finishTag
            return
        }
        if let running = vm.runningContext {
            selection = running.id
            return
        }
        guard selection != Self.finishTag else { return }
        guard let selected = vm.orderedContexts.first(where: { $0.id == selection }) else {
            selection = (vm.nextTarget ?? vm.orderedContexts.first)?.id ?? selection
            return
        }
        if selected.set.isCompleted, let next = vm.nextTarget {
            selection = next.id
        }
    }
}

// MARK: - Start countdown

/// Full-screen "3·2·1" pre-roll shown before the first set begins.
private struct CountdownOverlay: View {
    let value: Int

    var body: some View {
        ZStack {
            WK.bg.ignoresSafeArea()
            Text("\(value)")
                .font(.system(size: 150, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .foregroundStyle(WK.orange)
                .id(value)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
    }
}

// MARK: - Onset auto-start banner

/// Glanceable confirmation that the detector just auto-started a set, with a
/// single [撤销] to revert the rare false positive. Auto-dismisses if untouched.
private struct OnsetAutoStartBanner: View {
    let suggestion: OnsetSuggestion
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(SharedL10n.tr("watch.fitness.started"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WK.green)
                Text(SharedL10n.tr("watch.fitness.exercise_set_index", suggestion.exerciseName, suggestion.setIndex + 1))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onUndo) {
                Text(SharedL10n.tr("watch.fitness.undo"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WK.bg)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(WK.green, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WK.green.opacity(0.6), lineWidth: 1))
        .padding(.horizontal, 8)
        .task {
            // The undo window: banner fades on its own if the user does nothing.
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            onDismiss()
        }
    }
}

// MARK: - Set page

private struct SetPageView: View {
    let context: WatchWorkoutViewModel.SetContext
    let heartRate: Int
    let now: Date
    let restRemaining: Int?
    let isBusy: Bool
    let onStart: () -> Void
    let onComplete: () -> Void
    let onReopen: () -> Void

    private var setModel: FitnessSessionSet { context.set }
    private var isRunning: Bool { setModel.timerStatus == "running" }
    private var isCompleted: Bool { setModel.isCompleted }
    private var isTimeBased: Bool { context.exercise.isTimeBased }
    private var isDistanceBased: Bool { ExerciseTrackingDisplay.isDistanceBased(context.exercise.trackingType) }
    private var showsWeight: Bool { context.exercise.trackingType == "weight_reps" }

    private var weight: Double? { setModel.actualWeightKg ?? setModel.plannedWeightKg }
    private var reps: Int? { setModel.actualReps ?? setModel.plannedReps }
    private var duration: Int? { setModel.actualDurationSeconds ?? setModel.plannedDurationSeconds }
    private var distance: Double? { setModel.actualDistanceMeters ?? setModel.plannedDistanceMeters }

    private var runningElapsed: Int {
        let base = setModel.timerAccumulatedSeconds ?? 0
        let live = setModel.timerStartedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
        return base + live
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            topTimer
            Text(context.exercise.name)
                .font(.system(size: 25, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.68)
            if let note = context.exercise.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }

            if heartRate > 0 {
                HStack(spacing: 4) {
                    Text("\(heartRate)").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(WK.heart)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 4)

            HStack(alignment: .bottom) {
                metrics
                Spacer()
                actionButton
            }

            setChip
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(colors: tint, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var topTimer: some View {
        HStack(spacing: 4) {
            Image(systemName: isRunning ? "timer" : "clock").font(.system(size: 12, weight: .semibold))
            if isRunning {
                Text(WK.clock(runningElapsed)).monospacedDigit()
            } else if let restRemaining {
                Text(WK.clock(restRemaining)).monospacedDigit()
            } else {
                Text("--:--")
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))
    }

    @ViewBuilder
    private var metrics: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isTimeBased {
                if isDistanceBased {
                    Text(distanceText(distance)).font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                Text(durationText(duration ?? 0)).font(.system(size: isDistanceBased ? 22 : 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                if showsWeight {
                    Text(WK.weightText(weight)).font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                Text("x\(reps ?? 0)").font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        Button {
            if isCompleted { onReopen() }
            else if isRunning { onComplete() }
            else { onStart() }
        } label: {
            Image(systemName: buttonSymbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(isCompleted || isRunning ? .white : WK.bg)
                .frame(width: 58, height: 58)
                .background(buttonFill, in: Circle())
        }
        .buttonStyle(HapticButtonStyle())
        .disabled(isBusy)
        .overlay {
            if isBusy { ProgressView().tint(.white) }
        }
    }

    private var buttonSymbol: String {
        if isCompleted { return "checkmark" }
        if isRunning { return "checkmark" }
        return "play.fill"
    }

    private var buttonFill: Color {
        if isCompleted { return WK.green.opacity(0.5) }
        if isRunning { return WK.green }
        return .white
    }

    private var setChip: some View {
        Text(SharedL10n.tr("watch.fitness.set_progress", context.exerciseSetIndex + 1, context.exerciseSetCount))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(.white.opacity(0.18), in: Capsule())
            .padding(.top, 2)
    }

    private var tint: [Color] {
        if isCompleted { return [Color(hex: "1B4B36"), Color(hex: "0B2B1E")] }
        if isRunning { return [Color(hex: "7A1F3D"), Color(hex: "3A0E1E")] }
        return [Color(hex: "1E3A6B"), Color(hex: "0B1B36")]
    }

    private func durationText(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        return SharedL10n.tr("watch.fitness.duration_min_sec", safe / 60, safe % 60)
    }

    private func distanceText(_ meters: Double?) -> String {
        "\(Int((meters ?? 0).rounded()))m"
    }
}

// MARK: - Finish page

private struct FinishPageView: View {
    let elapsed: Int
    let volume: Double
    let sets: Int
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(SharedL10n.tr("watch.fitness.workout_complete")).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            HStack(spacing: 14) {
                stat(WK.clock(elapsed), SharedL10n.tr("watch.fitness.duration_label"))
                stat("\(sets)", SharedL10n.tr("watch.fitness.sets_label"))
            }
            stat(WK.weightText(volume), SharedL10n.tr("watch.fitness.total_volume"))

            Button(action: onFinish) {
                Text(SharedL10n.tr("common.done"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(WK.green, in: Capsule())
            }
            .buttonStyle(HapticButtonStyle())
            .padding(.top, 6)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(colors: [Color(hex: "1B4B36"), Color(hex: "0B2B1E")],
                           startPoint: .top,
                           endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - Controls page (swipe in from the first set)

/// Apple-Workout-style controls: total time, active calories, heart rate, and
/// End / Pause / Delete buttons.
private struct ControlsPageView: View {
    let elapsed: Int
    let activeKcal: Double
    let heartRate: Int
    let isPaused: Bool
    let onEnd: () -> Void
    let onPauseToggle: () -> Void
    let onDelete: () -> Void

    @ObservedObject private var recorder = WorkoutSessionRecorder.shared

    var body: some View {
        ZStack {
            WK.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(SharedL10n.tr("watch.fitness.total_time")).font(.system(size: 12)).foregroundStyle(WK.muted)
                    Text(clockHMS(elapsed))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WK.orange)

                    HStack {
                        Text(SharedL10n.tr("watch.fitness.active_energy")).font(.system(size: 13)).foregroundStyle(WK.muted)
                        Spacer()
                        Text("\(Int(activeKcal.rounded())) kcal")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    HStack {
                        Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(WK.heart)
                        Spacer()
                        Text(heartRate > 0 ? "\(heartRate) bpm" : "-- bpm")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 12) {
                        controlButton(symbol: "xmark", fill: WK.red, action: onEnd)
                        controlButton(symbol: isPaused ? "play.fill" : "pause.fill", fill: WK.surface, action: onPauseToggle)
                        controlButton(symbol: "trash", fill: WK.surface, tint: WK.red, action: onDelete)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    // Debug: continuous capture status (auto rep-detection).
                    Text(recorder.debugStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(WK.muted)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func controlButton(symbol: String, fill: Color, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 50, height: 50)
                .background(fill, in: Circle())
        }
        .buttonStyle(HapticButtonStyle())
    }

    private func clockHMS(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
