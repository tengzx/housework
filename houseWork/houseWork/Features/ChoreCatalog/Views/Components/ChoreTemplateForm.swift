//
//  ChoreTemplateForm.swift
//  houseWork
//
//  Form sheet to create or edit a chore template draft.
//

import SwiftUI

struct ChoreTemplateForm: View {
    @EnvironmentObject private var tagStore: TagStore
    @Binding var draft: ChoreTemplateDraft
    var isEditing: Bool
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
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(tagStore.tags) { tag in
                            let isSelected = selectedTags.contains { $0.caseInsensitiveCompare(tag.name) == .orderedSame }
                            Button {
                                toggleTag(named: tag.name)
                            } label: {
                                Text(tag.name)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Chore Template" : "New Chore Template")
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
    
    private var selectedTags: [String] {
        draft.tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private func toggleTag(named name: String) {
        var tags = selectedTags
        if let index = tags.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            tags.remove(at: index)
        } else {
            tags.append(name)
        }
        draft.tagsText = tags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        ChoreTemplateForm(draft: .constant(.init()), isEditing: false) { _ in }
            .environmentObject(TagStore())
    }
}
