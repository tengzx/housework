//
//  TagManagementView.swift
//  houseWork
//
//  CRUD interface for household tags.
//

import SwiftUI


struct TagManagementView: View {
    @EnvironmentObject private var tagStore: TagStore
    @State private var newTagName: String = ""
    @State private var editingTag: TagItem?
    @State private var editedName: String = ""
    
    var body: some View {
        List {
            Section("Existing tags") {
                if tagStore.tags.isEmpty {
                    Text("No tags yet. Add your first tag below.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tagStore.tags) { tag in
                        HStack {
                            Text(tag.name)
                            Spacer()
                            Button("Edit") {
                                editingTag = tag
                                editedName = tag.name
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onDelete(perform: tagStore.delete)
                }
            }
            
            Section("Add tag") {
                HStack {
                    TextField("Tag name", text: $newTagName)
                    Button {
                        tagStore.addTag(named: newTagName)
                        newTagName = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("Tags")
        .sheet(item: $editingTag) { tag in
            NavigationStack {
                Form {
                    TextField("Tag name", text: $editedName)
                }
                .navigationTitle("Rename Tag")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingTag = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            tagStore.rename(tag: tag, to: editedName)
                            editingTag = nil
                        }
                        .disabled(editedName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TagManagementView()
            .environmentObject(TagStore())
    }
}
