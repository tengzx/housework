import SwiftUI

// Tracking type display helpers
private let trackingTypeOptions: [(value: String, key: String)] = [
    ("weight_reps", "fitness.exercise.tracking.weight_reps"),
    ("reps_only", "fitness.exercise.tracking.reps_only"),
    ("time_only", "fitness.exercise.tracking.time_only"),
    ("distance_time", "fitness.exercise.tracking.distance_time"),
    ("cardio", "fitness.exercise.tracking.cardio"),
]

// MARK: - Form sheet

struct FitnessExerciseFormSheet: View {
    let existingExercise: FitnessExercise?
    // 同步闭包，在 @MainActor save() 里直接调，避免 async 闭包切换线程导致 EXC_BAD_ACCESS
    let onSave: (FitnessExercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedCategoryId: Int?
    @State private var trackingType: String
    @State private var categories: [ExerciseCategory] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(existingExercise: FitnessExercise? = nil, onSave: @escaping (FitnessExercise) -> Void) {
        self.existingExercise = existingExercise
        self.onSave = onSave
        _name = State(initialValue: existingExercise?.name ?? "")
        _selectedCategoryId = State(initialValue: existingExercise?.category?.id)
        _trackingType = State(initialValue: existingExercise?.trackingType ?? "weight_reps")
    }

    private var isCreateMode: Bool { existingExercise == nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("fitness.exercise.basic_info")) {
                    TextField(L10n.tr("fitness.exercise.name_required"), text: $name)

                    Picker(L10n.tr("fitness.exercise.category"), selection: $selectedCategoryId) {
                        Text(L10n.tr("fitness.exercise.uncategorized")).tag(Optional<Int>.none)
                        ForEach(categories) { cat in
                            Text(cat.name).tag(Optional<Int>.some(cat.id))
                        }
                    }
                }

                Section(L10n.tr("fitness.exercise.training_type")) {
                    Picker(L10n.tr("fitness.exercise.tracking_method"), selection: $trackingType) {
                        ForEach(trackingTypeOptions, id: \.value) { opt in
                            Text(L10n.tr(opt.key)).tag(opt.value)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if let err = errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(L10n.tr(isCreateMode ? "fitness.exercise.create_title" : "fitness.exercise.edit_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.cancel")) { Haptics.tap(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Haptics.tap()
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.tr(isCreateMode ? "common.create" : "common.save")).fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .task { await loadCategories() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func loadCategories() async {
        do {
            categories = try await FitnessAPIClient.exerciseCategories()
        } catch {}
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        let trimName = name.trimmingCharacters(in: .whitespaces)
        do {
            let saved: FitnessExercise
            if let existing = existingExercise {
                let resp = try await FitnessAPIClient.updateExercise(
                    id: existing.id,
                    name: trimName,
                    categoryId: selectedCategoryId,
                    trackingType: trackingType
                )
                let updatedCategory = categories.first { $0.id == selectedCategoryId }
                saved = FitnessExercise(
                    id: resp.id,
                    name: resp.name,
                    category: updatedCategory,
                    trackingType: trackingType,
                    isTimeBased: ExerciseTrackingDisplay.isTimeBased(trackingType),
                    supportsDistance: ExerciseTrackingDisplay.isDistanceBased(trackingType),
                    imageUrl: existing.imageUrl,
                    primaryMuscles: existing.primaryMuscles,
                    secondaryMuscles: existing.secondaryMuscles,
                    isSystem: resp.isSystem
                )
            } else {
                let resp = try await FitnessAPIClient.createExercise(
                    name: trimName,
                    categoryId: selectedCategoryId,
                    trackingType: trackingType
                )
                let cat = categories.first { $0.id == selectedCategoryId }
                saved = FitnessExercise(
                    id: resp.id,
                    name: resp.name,
                    category: cat,
                    trackingType: trackingType,
                    isTimeBased: ExerciseTrackingDisplay.isTimeBased(trackingType),
                    supportsDistance: ExerciseTrackingDisplay.isDistanceBased(trackingType),
                    imageUrl: nil,
                    primaryMuscles: [],
                    secondaryMuscles: [],
                    isSystem: resp.isSystem
                )
            }
            // 同步调用，此时仍在 @MainActor 上，不会切线程
            onSave(saved)
            dismiss()
        } catch {
            errorMessage = L10n.tr("fitness.exercise.save_failed")
            isSaving = false
        }
    }
}
