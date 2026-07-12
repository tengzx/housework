import SwiftUI
import Combine

// MARK: - Navigation payload

struct FitnessTemplateEditorPayload: Hashable {
    let id: Int?          // nil → 新建，尚未在服务端创建，保存时才创建
    let name: String
}

// MARK: - Draft models (local state)

struct DraftExercise: Identifiable {
    var id = UUID()
    var templateExerciseId: Int?       // nil → new
    let exerciseId: Int
    let exerciseName: String
    let categoryName: String
    let trackingType: String
    let imageUrl: String?
    var sortOrder: Int
    var sets: [DraftSet]

    var isTimeBased: Bool { ExerciseTrackingDisplay.isTimeBased(trackingType) }
    var thirdLabel: String { ExerciseTrackingDisplay.thirdColumnLabel(trackingType) }
    var showWeightColumn: Bool { trackingType == "weight_reps" }
    var showDistanceColumn: Bool { ExerciseTrackingDisplay.isDistanceBased(trackingType) }
    var showSecondColumn: Bool { ExerciseTrackingDisplay.showsSecondColumn(trackingType) }
    var secondColumnLabel: String { ExerciseTrackingDisplay.secondColumnLabel(trackingType) }
}

struct DraftSet: Identifiable {
    var id = UUID()
    var templateSetId: Int?            // nil → new
    var setOrder: Int
    var weightKgText: String           // editable string for weight field
    var repsText: String               // editable string for reps/duration field
    var restSecondsText: String

    var targetWeightKg: Double? { Double(weightKgText) }
    var targetReps: Int? { Int(repsText) }
    var targetDurationSeconds: Int? { Int(repsText) }
    var restSeconds: Int { Int(restSecondsText) ?? 120 }
}

// MARK: - ViewModel

@MainActor
final class TemplateEditorViewModel: ObservableObject {
    private(set) var templateId: Int?
    @Published var templateName: String
    @Published var exercises: [DraftExercise] = []
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var isSaving = false
    @Published private(set) var isDeleting = false
    @Published var errorMessage: String?

    private var deletedExerciseIds: [Int] = []
    private var deletedSetIds: [Int] = []
    private var originalTemplateName: String

    private var trimmedTemplateName: String {
        templateName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool { !trimmedTemplateName.isEmpty && !isSaving && !isDeleting }

    init(id: Int?, name: String) {
        self.templateId = id
        self.templateName = name
        self.originalTemplateName = name
    }

    func loadDetail() async {
        guard let templateId, exercises.isEmpty else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            let detail = try await FitnessAPIClient.templateDetail(id: templateId)
            templateName = detail.name
            originalTemplateName = detail.name
            exercises = detail.exercises.map { ex in
                DraftExercise(
                    templateExerciseId: ex.templateExerciseId,
                    exerciseId: ex.exerciseId,
                    exerciseName: ex.name,
                    categoryName: ex.categoryName ?? "",
                    trackingType: ex.trackingType,
                    imageUrl: ex.imageUrl,
                    sortOrder: ex.sortOrder,
                    sets: ex.sets.map { s in
                        let isDistanceType = ExerciseTrackingDisplay.isDistanceBased(ex.trackingType)
                        return DraftSet(
                            templateSetId: s.templateSetId,
                            setOrder: s.setOrder,
                            weightKgText: {
                                if isDistanceType {
                                    return s.targetDistanceMeters.map { String(Int($0)) } ?? "0"
                                }
                                return s.targetWeightKg.map { String(Int($0)) } ?? "0"
                            }(),
                            repsText: {
                                if let r = s.targetReps { return String(r) }
                                if let d = s.targetDurationSeconds { return String(d) }
                                return "0"
                            }(),
                            restSecondsText: String(s.restSeconds ?? ex.restSeconds ?? 120)
                        )
                    }
                )
            }
        } catch {}
    }

    // Called when library confirms selection
    func applyLibrarySelection(_ selected: [FitnessExercise]) {
        let selectedIds = Set(selected.map { $0.id })

        // Remove deselected exercises (track their IDs for deletion)
        let removed = exercises.filter { !selectedIds.contains($0.exerciseId) }
        deletedExerciseIds.append(contentsOf: removed.compactMap { $0.templateExerciseId })

        // Keep existing exercises that are still selected
        let kept = exercises.filter { selectedIds.contains($0.exerciseId) }
        let keptIds = Set(kept.map { $0.exerciseId })

        // Add newly selected exercises with default sets
        let added: [DraftExercise] = selected
            .filter { !keptIds.contains($0.id) }
            .map { ex in
                let defaultSet = DraftSet(
                    templateSetId: nil,
                    setOrder: 1,
                    weightKgText: ExerciseTrackingDisplay.isDistanceBased(ex.trackingType) ? "100" : (ex.isTimeBased ? "0" : "10"),
                    repsText: ex.isTimeBased ? "30" : "12",
                    restSecondsText: "120"
                )
                return DraftExercise(
                    templateExerciseId: nil,
                    exerciseId: ex.id,
                    exerciseName: ex.name,
                    categoryName: ex.category?.name ?? "",
                    trackingType: ex.trackingType,
                    imageUrl: ex.imageUrl,
                    sortOrder: kept.count + 1,
                    sets: [defaultSet]
                )
            }

        exercises = kept + added
        // Re-assign sortOrder
        for i in exercises.indices { exercises[i].sortOrder = i + 1 }
    }

    func addSet(to exerciseId: UUID) {
        guard let idx = exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let last = exercises[idx].sets.last
        let newSet = DraftSet(
            templateSetId: nil,
            setOrder: exercises[idx].sets.count + 1,
            weightKgText: last?.weightKgText ?? "10",
            repsText: last?.repsText ?? "12",
            restSecondsText: last?.restSecondsText ?? "120"
        )
        exercises[idx].sets.append(newSet)
    }

    func deleteSet(exerciseId: UUID, setId: UUID) {
        guard let exIdx = exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        if let setIdx = exercises[exIdx].sets.firstIndex(where: { $0.id == setId }) {
            if let dbId = exercises[exIdx].sets[setIdx].templateSetId {
                deletedSetIds.append(dbId)
            }
            exercises[exIdx].sets.remove(at: setIdx)
            // Renumber
            for i in exercises[exIdx].sets.indices { exercises[exIdx].sets[i].setOrder = i + 1 }
        }
        // Remove exercise if all sets deleted
        if exercises[exIdx].sets.isEmpty {
            removeExercise(id: exerciseId)
        }
    }

    func removeExercise(id: UUID) {
        if let idx = exercises.firstIndex(where: { $0.id == id }) {
            if let dbId = exercises[idx].templateExerciseId {
                deletedExerciseIds.append(dbId)
            }
            exercises.remove(at: idx)
            for i in exercises.indices { exercises[i].sortOrder = i + 1 }
        }
    }

    func moveExercise(from source: IndexSet, to destination: Int) {
        exercises.move(fromOffsets: source, toOffset: destination)
        for i in exercises.indices { exercises[i].sortOrder = i + 1 }
    }

    func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let nameToSave = trimmedTemplateName
        guard !nameToSave.isEmpty else {
            errorMessage = SharedL10n.tr("fitness.template.name_required")
            return
        }
        let saveExercises = exercises.map { ex in
            SaveExerciseItem(
                templateExerciseId: ex.templateExerciseId,
                exerciseId: ex.exerciseId,
                sortOrder: ex.sortOrder,
                restSeconds: 120,
                note: "",
                sets: ex.sets.map { s in
                    SaveSetItem(
                        templateSetId: s.templateSetId,
                        setOrder: s.setOrder,
                        setType: "normal",
                        targetWeightKg: ex.showWeightColumn ? s.targetWeightKg : nil,
                        targetReps: ex.isTimeBased ? nil : s.targetReps,
                        targetDurationSeconds: ex.isTimeBased ? s.targetDurationSeconds : nil,
                        targetDistanceMeters: ex.showDistanceColumn ? Double(s.weightKgText) : nil,
                        restSeconds: s.restSeconds,
                        note: ""
                    )
                }
            )
        }
        let req = SaveTemplateStructureRequest(
            exercises: saveExercises,
            deletedTemplateExerciseIds: deletedExerciseIds,
            deletedTemplateSetIds: deletedSetIds
        )
        do {
            let id: Int
            if let existingId = templateId {
                id = existingId
                if nameToSave != originalTemplateName {
                    _ = try await FitnessAPIClient.updateTemplate(
                        id: id,
                        name: nameToSave,
                        trainingTheme: nil,
                        description: nil
                    )
                    templateName = nameToSave
                    originalTemplateName = nameToSave
                }
            } else {
                // 新建模板：此时才真正在服务端创建
                let resp = try await FitnessAPIClient.createTemplate(name: nameToSave, description: nil, trainingTheme: nil)
                id = resp.id
                templateId = resp.id
                templateName = nameToSave
                originalTemplateName = nameToSave
            }
            _ = try await FitnessAPIClient.saveTemplateStructure(id: id, request: req)
            // Clear deletion tracking after successful save
            deletedExerciseIds = []
            deletedSetIds = []
            // Reload to get server-assigned IDs
            exercises = []
            await loadDetail()
        } catch {
            errorMessage = SharedL10n.tr("fitness.template.save_failed")
        }
    }

    func deleteTemplate() async -> Bool {
        // 尚未创建的新模板：无需请求服务端，直接视为可关闭
        guard let templateId else { return true }
        guard !isDeleting else { return false }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await FitnessAPIClient.deleteTemplate(id: templateId)
            return true
        } catch {
            errorMessage = SharedL10n.tr("fitness.template.delete_failed")
            return false
        }
    }
}

// MARK: - Editor View

struct FitnessTemplateEditorView: View {
    let payload: FitnessTemplateEditorPayload
    let onSaved: @MainActor () async -> Void
    let onDeleted: @MainActor () async -> Void

    @StateObject private var vm: TemplateEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showLibrary = false
    @State private var showDeleteConfirm = false
    @State private var progressTarget: ExerciseProgressTarget?
    @State private var editingSetId: UUID?

    init(
        payload: FitnessTemplateEditorPayload,
        onSaved: @escaping @MainActor () async -> Void,
        onDeleted: @escaping @MainActor () async -> Void
    ) {
        self.payload = payload
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _vm = StateObject(wrappedValue: TemplateEditorViewModel(id: payload.id, name: payload.name))
    }

    private var subText: String {
        vm.exercises.isEmpty
            ? SharedL10n.tr("fitness.template.empty_exercises")
            : SharedL10n.tr("fitness.template.summary", vm.exercises.count, vm.exercises.reduce(0) { $0 + $1.sets.count })
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }

            VStack(spacing: 0) {
                navRow
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollViewReader { proxy in
                    List {
                        // Title + subtitle (no card)
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                TextField(SharedL10n.tr("fitness.template.name"), text: $vm.templateName)
                                    .font(.system(size: 28, weight: .heavy))
                                    .foregroundStyle(Color(hex: "1C1C1E"))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                Text(subText)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color(hex: "9A9AA0"))
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 2, trailing: 20))
                        }

                        if vm.exercises.isEmpty && !vm.isLoadingDetail {
                            Section {
                                emptyState
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
                            }
                        } else {
                            Section {
                                ForEach($vm.exercises) { $ex in
                                    ExerciseCard(
                                        exercise: $ex,
                                        vm: vm,
                                        onProgress: {
                                            progressTarget = ExerciseProgressTarget(
                                                exerciseId: ex.exerciseId,
                                                name: ex.exerciseName,
                                                trackingType: ex.trackingType
                                            )
                                        },
                                        onEditSet: { editingSetId = $0 }
                                    )
                                    .listRowInsets(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                }
                                .onMove { source, destination in
                                    Haptics.tap()
                                    vm.moveExercise(from: source, to: destination)
                                }
                            }
                        }

                        // Bottom spacer so the fixed bottom bar never covers content
                        Section {
                            Color.clear
                                .frame(height: 90)
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
                        // position so the keyboard doesn't cover it.
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("set-\(setId)", anchor: UnitPoint(x: 0.5, y: 0.35))
                        }
                    }
                }
            }

            // Bottom bar
            bottomBar
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showLibrary) {
            FitnessExerciseLibrarySheet(
                preselected: vm.exercises.map {
                    FitnessExercise.lightweight(
                        id: $0.exerciseId,
                        name: $0.exerciseName,
                        categoryName: $0.categoryName,
                        trackingType: $0.trackingType
                    )
                }
            ) { selected in
                vm.applyLibrarySelection(selected)
            }
        }
        .sheet(item: $progressTarget) { target in
            ExerciseProgressSheet(target: target)
        }
        .alert(SharedL10n.tr("common.error"), isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button(SharedL10n.tr("common.ok")) { Haptics.tap(); vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .alert(
            SharedL10n.tr("fitness.template.delete_confirm", vm.templateName),
            isPresented: $showDeleteConfirm
        ) {
            Button(SharedL10n.tr("common.cancel"), role: .cancel) { Haptics.tap() }
            Button(SharedL10n.tr("common.delete"), role: .destructive) {
                Haptics.tap()
                Task {
                    if await vm.deleteTemplate() {
                        await onDeleted()
                    }
                }
            }
        } message: {
            Text(SharedL10n.tr("fitness.template.delete_message"))
        }
        .task { await vm.loadDetail() }
    }

    // MARK: Nav row

    private var navRow: some View {
        HStack {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
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
            Menu {
                Button(role: .destructive) {
                    Haptics.tap()
                    showDeleteConfirm = true
                } label: {
                    Label(SharedL10n.tr("fitness.template.delete_action"), systemImage: "trash")
                }
            } label: {
                Circle()
                    .fill(Color(hex: "F1F1F4"))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                    )
            }
            .disabled(vm.isDeleting)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: "F6F6F8"))
                .frame(height: 200)
                .padding(.horizontal, 16)

            VStack(spacing: 12) {
                Text(SharedL10n.tr("fitness.template.empty_exercises"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Text(SharedL10n.tr("fitness.template.empty_hint"))
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "7C7C82"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Button { Haptics.tap(); showLibrary = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text(SharedL10n.tr("fitness.template.add_exercise"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 13)
                    .background(Color(hex: "1C1C1E"), in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
                }
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { Haptics.tap(); showLibrary = true } label: {
                Text(SharedL10n.tr("fitness.template.add_exercise"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(hex: "F1F1F4"), in: Capsule())
            }

            Button {
                Haptics.tap()
                Task {
                    await vm.save()
                    if vm.errorMessage == nil {
                        await onSaved()
                        dismiss()
                    }
                }
            } label: {
                Group {
                    if vm.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(SharedL10n.tr("common.save"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundStyle(vm.canSave ? .white : Color(hex: "9A9AA0"))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    vm.canSave ? Color(hex: "1C1C1E") : Color(hex: "EEEEF1"),
                    in: Capsule()
                )
            }
            .disabled(!vm.canSave)
            .animation(.easeInOut(duration: 0.2), value: vm.canSave)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 30)
        .background(
            LinearGradient(colors: [.white, .white.opacity(0)],
                           startPoint: .bottom, endPoint: .top)
            .ignoresSafeArea()
        )
    }
}

// MARK: - Exercise Card (one draggable list row per exercise)

private struct ExerciseCard: View {
    @Binding var exercise: DraftExercise
    let vm: TemplateEditorViewModel
    let onProgress: () -> Void
    let onEditSet: (UUID?) -> Void
    @State private var showRestInputs = false

    var body: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 8)

            columnHeaderRow
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ForEach($exercise.sets) { $set in
                SetRow(
                    set: $set,
                    isTimeBased: exercise.isTimeBased,
                    showSecondColumn: exercise.showSecondColumn,
                    secondPlaceholder: exercise.showDistanceColumn ? SharedL10n.tr("fitness.unit.meter") : "kg",
                    showRestInput: showRestInputs,
                    onFocusChange: { isEditing in onEditSet(isEditing ? set.id : nil) },
                    onDelete: { vm.deleteSet(exerciseId: exercise.id, setId: set.id) }
                )
                .id("set-\(set.id)")
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
                Text(exercise.exerciseName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Text(exercise.categoryName.isEmpty ? "——" : exercise.categoryName)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "9A9AA0"))
            }

            Spacer()

            Button {
                showRestInputs.toggle()
            } label: {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(showRestInputs ? Color(hex: "1C1C1E") : Color.white)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "timer")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(showRestInputs ? .white : Color(hex: "6F6F76"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(showRestInputs ? Color(hex: "1C1C1E") : Color(hex: "EAEAEE"), lineWidth: 1)
                    )
            }
            .buttonStyle(HapticButtonStyle())

            Menu {
                Button(role: .destructive) {
                    Haptics.tap()
                    vm.removeExercise(id: exercise.id)
                } label: {
                    Label(SharedL10n.tr("fitness.template.delete_exercise"), systemImage: "trash")
                }
            } label: {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: "EAEAEE"), lineWidth: 1)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text("···")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                            .offset(y: -3)
                    )
            }
        }
    }

    private var columnHeaderRow: some View {
        HStack(spacing: 10) {
            Text(SharedL10n.tr("fitness.template.set_short")).frame(width: 44)
            if exercise.showSecondColumn { Text(exercise.secondColumnLabel).frame(maxWidth: .infinity) }
            Text(exercise.thirdLabel).frame(maxWidth: .infinity)
            Spacer().frame(width: 30)
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
                    Text(SharedL10n.tr("fitness.template.progress"))
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
                vm.addSet(to: exercise.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text(SharedL10n.tr("fitness.template.add_set"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color(hex: "1C1C1E"))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
        }
        .frame(height: 44)
    }
}

// MARK: - Exercise card background

/// Wraps a whole exercise card (a single list row) in the rounded white fill and
/// soft drop shadow. Each exercise is now one reorderable list row, so the card
/// is drawn once around the row's content rather than pieced together across
/// several row backgrounds.
private struct ExerciseCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
    }
}

extension View {
    /// Draws the rounded white card fill + shadow behind an exercise card row.
    func exerciseCardBackground() -> some View { modifier(ExerciseCardBackground()) }
}

// MARK: - Set Row

private enum TemplateSetField: Hashable { case second, third }

private struct SetRow: View {
    @Binding var set: DraftSet
    let isTimeBased: Bool
    let showSecondColumn: Bool
    let secondPlaceholder: String
    let showRestInput: Bool
    let onFocusChange: (Bool) -> Void
    let onDelete: () -> Void

    @FocusState private var focused: TemplateSetField?

    private var thirdDisplayText: String {
        guard isTimeBased, !set.repsText.isEmpty, let secs = Int(set.repsText) else { return set.repsText }
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("\(set.setOrder)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .frame(width: 44, height: 40)
                    .background(
                        Circle()
                            .fill(.clear)
                            .frame(width: 34, height: 34)
                            .overlay(Circle().stroke(Color(hex: "D8D8DE"), lineWidth: 1.5))
                    )

                if showSecondColumn {
                    valueField(field: .second, keyboard: .decimalPad, placeholder: secondPlaceholder, text: $set.weightKgText)
                }

                valueField(field: .third, keyboard: .numberPad, placeholder: "--", text: Binding(
                    get: { (isTimeBased && focused != .third) ? thirdDisplayText : set.repsText },
                    set: { set.repsText = $0 }
                ))

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
            }

            if showRestInput {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "6F6F76"))
                    Text(SharedL10n.tr("fitness.template.rest"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "6F6F76"))
                    TextField("120", text: $set.restSecondsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .frame(width: 76, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color(hex: "EEEEF1"), lineWidth: 1)
                        )
                    Text(SharedL10n.tr("fitness.unit.second"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "6F6F76"))
                    Spacer()
                }
                .padding(.leading, 54)
            }
        }
        .onChange(of: focused) { _, new in
            onFocusChange(new != nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { notification in
            if let textField = notification.object as? UITextField {
                textField.selectAll(nil)
            }
        }
    }

    @ViewBuilder
    private func valueField(
        field: TemplateSetField,
        keyboard: UIKeyboardType,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .focused($focused, equals: field)
            .multilineTextAlignment(.center)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color(hex: "1C1C1E"))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(fieldBackground(isFocused: focused == field))
    }

    // 输入框背景样式
    @ViewBuilder
    private func fieldBackground(isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isFocused ? Color(hex: "FFEDE3") : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isFocused ? Color(hex: "FF7847") : Color(hex: "D8D8DE"), lineWidth: isFocused ? 2 : 1.5)
            )
    }
}
