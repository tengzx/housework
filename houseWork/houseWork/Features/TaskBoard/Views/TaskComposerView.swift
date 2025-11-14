//
//  TaskComposerView.swift
//  houseWork
//
//  Light-weight form for creating an ad-hoc task on the board.
//

import SwiftUI

struct TaskComposerView: View {
    @EnvironmentObject private var taskStore: TaskBoardStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var tagStore: TagStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var details: String = ""
    @State private var roomTag: String = "General"
    @State private var selectingTag = false
    @State private var score: Int = 10
    @State private var dueDate: Date = Date().addingTimeInterval(60 * 60 * 24)
    @State private var estimatedMinutes: Int = 30
    @State private var isSaving = false
    @State private var localError: String?
    
    var body: some View {
        navigationContainer {
            Form {
                Section(LocalizedStringKey("taskBoard.editor.section.basics")) {
                    TextField(LocalizedStringKey("taskBoard.editor.field.title"), text: $title)
                    descriptionField
                }
                
                Section(LocalizedStringKey("taskBoard.editor.section.scheduling")) {
                    DatePicker(LocalizedStringKey("taskBoard.detail.dueDate"), selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    HStack {
                        Text(LocalizedStringKey("taskBoard.editor.field.score"))
                        Spacer()
                        TextField(LocalizedStringKey("taskBoard.editor.field.score"), value: $score, format: .number)
                            .multilineTextAlignment(.trailing)
#if os(iOS)
                            .keyboardType(.numberPad)
#endif
                            .frame(width: 80)
                        Stepper("", value: $score, in: 5...100, step: 5)
                            .labelsHidden()
                    }
                    Stepper(value: $estimatedMinutes, in: 5...240, step: 5) {
                        HStack {
                            Text(LocalizedStringKey("taskBoard.editor.field.estimatedTime"))
                            Spacer()
                            Text("\(estimatedMinutes) min")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section(LocalizedStringKey("taskBoard.editor.section.tags")) {
                    Picker(LocalizedStringKey("taskBoard.editor.field.roomTag"), selection: $roomTag) {
                        Text(LocalizedStringKey("taskBoard.editor.field.general")).tag("General")
                        ForEach(tagStore.tags) { tag in
                            Text(tag.name).tag(tag.name)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                if let localError {
                    Section {
                        Text(localError)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(LocalizedStringKey("taskBoard.sheet.taskComposer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey("common.save")) { saveTask() }
                        .disabled(!canSave || isSaving)
                }
            }
        }
    }
    
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func saveTask() {
        guard canSave else { return }
        localError = nil
        isSaving = true
        Task {
            let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
            let success = await taskStore.createTask(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                details: trimmedDetails.isEmpty ? String(localized: "task.details.empty") : trimmedDetails,
                dueDate: dueDate,
                score: score,
                roomTag: roomTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "General" : roomTag,
                assignedMembers: authStore.currentUser.map { [$0] } ?? [],
                estimatedMinutes: estimatedMinutes
            )
            await MainActor.run {
                isSaving = false
                if success {
                    dismiss()
                } else {
                    localError = taskStore.mutationError ?? String(localized: "taskComposer.error.createFailed")
                }
            }
        }
    }
}

private extension TaskComposerView {
    var descriptionField: some View {
        Group {
            if #available(iOS 16.0, *) {
                TextField(LocalizedStringKey("taskBoard.editor.field.details"), text: $details, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
            } else {
                TextEditor(text: $details)
                    .frame(minHeight: 80)
            }
        }
    }
}

#Preview {
    navigationContainer {
        TaskComposerView()
            .environmentObject(TaskBoardStore(previewTasks: TaskItem.fixtures()))
            .environmentObject(AuthStore())
            .environmentObject(TagStore(householdStore: HouseholdStore()))
    }
}
