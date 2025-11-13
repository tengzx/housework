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
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Title", text: $title)
                    TextField("Details", text: $details, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
                
                Section("Scheduling") {
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    HStack {
                        Text("Score")
                        Spacer()
                        TextField("Score", value: $score, format: .number)
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
                            Text("Estimated Time")
                            Spacer()
                            Text("\(estimatedMinutes) min")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Tags") {
                    Picker("Room / Tag", selection: $roomTag) {
                        Text("General").tag("General")
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
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTask() }
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
                details: trimmedDetails.isEmpty ? "No details yet." : trimmedDetails,
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
                    localError = taskStore.mutationError ?? "Failed to create task."
                }
            }
        }
    }
}

#Preview {
    TaskComposerView()
        .environmentObject(TaskBoardStore(previewTasks: TaskItem.fixtures()))
        .environmentObject(AuthStore())
}
