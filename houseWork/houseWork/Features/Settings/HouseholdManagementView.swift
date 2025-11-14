//
//  HouseholdManagementView.swift
//  houseWork
//
//  Manage available households stored in Firestore.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HouseholdManagementView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var showAddSheet = false
    @State private var editingHousehold: HouseholdSummary?
    @State private var draftName: String = ""
    @State private var inviteCodeToShare: String?
    @State private var inviteHouseholdName: String = ""
    @State private var joinCode: String = ""
    @State private var joinStatus: JoinStatus?
    @State private var isJoining = false
    
    private struct JoinStatus: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }
    
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
                            if let code = summary.inviteCode {
                                Text("Invite code: \(code)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
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
                        Menu {
                            Button("Invite") {
                                Task { await generateInvite(for: summary) }
                            }
                            Button("Rename") {
                                editingHousehold = summary
                                draftName = summary.name
                            }
                            Button("Delete", role: .destructive) {
                                Task { await delete(summary: summary) }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            
            Section("Join via Code") {
                TextField("Invite code", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                if let joinStatus {
                    Text(joinStatus.message)
                        .font(.caption)
                        .foregroundStyle(joinStatus.isError ? Color.red : Color.green)
                }
                Button {
                    Task { await joinHouseholdByCode() }
                } label: {
                    if isJoining {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text("Join Household")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoining)
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
        .alert(inviteAlertTitle, isPresented: Binding(
            get: { inviteCodeToShare != nil },
            set: { if !$0 { inviteCodeToShare = nil } }
        )) {
            Button("Copy") {
                if let code = inviteCodeToShare {
#if canImport(UIKit)
                    UIPasteboard.general.string = code
#endif
                }
                inviteCodeToShare = nil
            }
            Button("Close", role: .cancel) {
                inviteCodeToShare = nil
            }
        } message: {
            if let code = inviteCodeToShare {
                Text("Share this code with others to let them join \"\(inviteHouseholdName)\".\n\nCode: \(code)")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            navigationContainer {
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
            navigationContainer {
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
    
    private var inviteAlertTitle: String {
        "Invite Code"
    }
    
    private func delete(at offsets: IndexSet) {
        let items = offsets.compactMap { householdStore.households.indices.contains($0) ? householdStore.households[$0] : nil }
        Task {
            for summary in items {
                await householdStore.delete(household: summary)
            }
        }
    }
    
    private func delete(summary: HouseholdSummary) async {
        await householdStore.delete(household: summary)
    }
    
    private func generateInvite(for summary: HouseholdSummary) async {
        let code = await householdStore.refreshInviteCode(for: summary)
        await MainActor.run {
            if let code {
                inviteCodeToShare = code
                inviteHouseholdName = summary.name
            }
        }
    }
    
    private func joinHouseholdByCode() async {
        let code = joinCode
        joinStatus = nil
        isJoining = true
        let success = await householdStore.joinHousehold(using: code)
        await MainActor.run {
            isJoining = false
            if success {
                joinStatus = JoinStatus(message: "Joined household successfully.", isError: false)
                joinCode = ""
            } else {
                joinStatus = JoinStatus(message: householdStore.error ?? "Unable to join household.", isError: true)
            }
        }
    }
}

#Preview {
    HouseholdManagementView()
        .environmentObject(HouseholdStore())
}
