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
            if tagStore.isLoading {
                ProgressView(LocalizedStringKey("tagManagement.loading"))
            }
            Section(LocalizedStringKey("tagManagement.section.existing")) {
                if tagStore.tags.isEmpty && !tagStore.isLoading {
                    Text(LocalizedStringKey("tagManagement.placeholder.none"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tagStore.tags) { tag in
                        HStack {
                            Text(tag.name)
                            Spacer()
                            Button(LocalizedStringKey("common.edit")) {
                                editingTag = tag
                                editedName = tag.name
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onDelete(perform: tagStore.delete)
                }
            }
            
            Section(LocalizedStringKey("tagManagement.section.add")) {
                HStack {
                    TextField(LocalizedStringKey("tagManagement.field.name"), text: $newTagName)
                    Button {
                        let name = newTagName
                        Task {
                            await tagStore.addTag(named: name)
                            await MainActor.run { newTagName = "" }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle(LocalizedStringKey("tagManagement.nav.title"))
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            #endif
        }
        .overlay(alignment: .bottom) {
            if let error = tagStore.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.red.opacity(0.8), in: Capsule())
                    .padding()
            }
        }
        .sheet(item: $editingTag) { tag in
            navigationContainer {
                Form {
                    TextField(LocalizedStringKey("tagManagement.field.name"), text: $editedName)
                }
                .navigationTitle(LocalizedStringKey("tagManagement.form.renameTitle"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(LocalizedStringKey("common.cancel")) { editingTag = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(LocalizedStringKey("common.save")) {
                            let name = editedName
                            Task {
                                await tagStore.rename(tag: tag, to: name)
                                await MainActor.run { editingTag = nil }
                            }
                        }
                        .disabled(editedName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}

#Preview {
    let householdStore = HouseholdStore()
    navigationContainer {
        TagManagementView()
            .environmentObject(householdStore)
            .environmentObject(TagStore(householdStore: householdStore))
    }
}
