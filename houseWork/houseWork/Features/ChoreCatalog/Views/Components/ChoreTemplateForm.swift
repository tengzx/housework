//
//  ChoreTemplateForm.swift
//  houseWork
//
//  Form sheet to create or edit a chore template draft.
//

import SwiftUI

struct ChoreTemplateForm: View {
    @Binding var draft: ChoreTemplateDraft
    var onSave: (ChoreTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section("Basics") {
                TextField("Title", text: $draft.title)
                TextField("Description", text: $draft.details, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
            }
            
            Section("Scoring & Effort") {
                Stepper(value: $draft.baseScore, in: 5...100, step: 5) {
                    HStack {
                        Text("Base Score")
                        Spacer()
                        Text("\(draft.baseScore) pts")
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $draft.estimatedMinutes, in: 5...180, step: 5) {
                    HStack {
                        Text("Est. Minutes")
                        Spacer()
                        Text("\(draft.estimatedMinutes) min")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("Classification") {
                Picker("Frequency", selection: $draft.frequency) {
                    ForEach(ChoreFrequency.allCases) { frequency in
                        Text(frequency.label).tag(frequency)
                    }
                }
                TextField("Tags (comma separated)", text: $draft.tagsText)
            }
        }
        .navigationTitle("New Chore Template")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveTemplate() }
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
    
    private func saveTemplate() {
        guard let template = draft.buildTemplate() else { return }
        onSave(template)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ChoreTemplateForm(draft: .constant(.init())) { _ in }
    }
}
