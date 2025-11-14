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
            Section(LocalizedStringKey("catalog.form.section.basics")) {
                TextField(LocalizedStringKey("catalog.form.field.title"), text: $draft.title)
                descriptionField
            }
            
            Section(LocalizedStringKey("catalog.form.section.scoring")) {
                Stepper(value: $draft.baseScore, in: 5...100, step: 5) {
                    HStack {
                        Text(LocalizedStringKey("catalog.form.field.baseScore"))
                        Spacer()
                        Text(pointsText)
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $draft.estimatedMinutes, in: 5...180, step: 5) {
                    HStack {
                        Text(LocalizedStringKey("catalog.form.field.estimatedMinutes"))
                        Spacer()
                        Text(minutesText)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section(LocalizedStringKey("catalog.form.section.classification")) {
                Picker(LocalizedStringKey("catalog.form.field.frequency"), selection: $draft.frequency) {
                    ForEach(ChoreFrequency.allCases) { frequency in
                        Text(frequency.localizedLabel).tag(frequency)
                    }
                }
                TextField(LocalizedStringKey("catalog.form.field.tags"), text: $draft.tagsText)
                
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
        .navigationTitle(isEditing ? LocalizedStringKey("catalog.form.nav.edit") : LocalizedStringKey("catalog.form.nav.new"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(LocalizedStringKey("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(LocalizedStringKey("common.save")) { saveTemplate() }
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
    
    private var descriptionField: some View {
        Group {
            if #available(iOS 16.0, *) {
                TextField(LocalizedStringKey("catalog.form.field.description"), text: $draft.details, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
            } else {
                TextEditor(text: $draft.details)
                    .frame(minHeight: 80)
            }
        }
    }
    
    private var pointsText: String {
        let template = String(localized: "catalog.row.points")
        return String(format: template, draft.baseScore)
    }
    
    private var minutesText: String {
        let template = String(localized: "catalog.row.minutes")
        return String(format: template, draft.estimatedMinutes)
    }
}

#Preview {
    let householdStore = HouseholdStore()
    navigationPreviewContainer {
        ChoreTemplateForm(draft: .constant(.init()), isEditing: false) { _ in }
            .environmentObject(TagStore(householdStore: householdStore))
    }
}
