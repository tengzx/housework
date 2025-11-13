//
//  HouseholdManagementView.swift
//  houseWork
//
//  Manage available households stored in Firestore.
//

import SwiftUI

struct HouseholdManagementView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var showAddSheet = false
    @State private var editingHousehold: HouseholdSummary?
    @State private var draftName: String = ""
    
    var body: some View {
        List {
            if householdStore.isLoading {
                ProgressView()
            }
            
            Section("Households") {
                ForEach(householdStore.households) { summary in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(summary.name)
                            Text(summary.id)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if summary.id == householdStore.householdId {
                            Label("Active", systemImage: "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.green)
                        } else {
                            Button("Use") {
                                householdStore.select(summary)
                            }
                        }
                        Button("Rename") {
                            editingHousehold = summary
                            draftName = summary.name
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Households")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    draftName = ""
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                Form {
                    TextField("Household name", text: $draftName)
                }
                .navigationTitle("New Household")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            let name = draftName
                            Task {
                                let success = await householdStore.createHousehold(named: name)
                                await MainActor.run {
                                    if success { showAddSheet = false }
                                }
                            }
                        }
                        .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .sheet(item: $editingHousehold) { summary in
            NavigationStack {
                Form {
                    TextField("Household name", text: $draftName)
                }
                .navigationTitle("Rename Household")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingHousehold = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let name = draftName
                            Task {
                                await householdStore.rename(household: summary, to: name)
                                await MainActor.run { editingHousehold = nil }
                            }
                        }
                        .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
    
    private func delete(at offsets: IndexSet) {
        let items = offsets.compactMap { householdStore.households.indices.contains($0) ? householdStore.households[$0] : nil }
        Task {
            for summary in items {
                await householdStore.delete(household: summary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        HouseholdManagementView()
            .environmentObject(HouseholdStore())
    }
}
