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
            
            Section(LocalizedStringKey("householdManagement.section.list")) {
                ForEach(householdStore.households) { summary in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(summary.name)
                            Text(summary.id)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let code = summary.inviteCode {
                                Text("householdManagement.inviteCode.format \(code)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if summary.id == householdStore.householdId {
                            Label(LocalizedStringKey("householdManagement.status.active"), systemImage: "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.green)
                        } else {
                            Button(LocalizedStringKey("settings.household.use")) {
                                householdStore.select(summary)
                            }
                        }
                        Menu {
                            Button(LocalizedStringKey("householdManagement.menu.invite")) {
                                Task { await generateInvite(for: summary) }
                            }
                            Button(LocalizedStringKey("householdManagement.menu.rename")) {
                                editingHousehold = summary
                                draftName = summary.name
                            }
                            Button(LocalizedStringKey("taskBoard.action.delete"), role: .destructive) {
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
            
            Section(LocalizedStringKey("householdManagement.section.join")) {
                TextField(LocalizedStringKey("householdManagement.field.inviteCode"), text: $joinCode)
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
                        Text(LocalizedStringKey("householdManagement.join.button"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoining)
            }
        }
        .navigationTitle(LocalizedStringKey("householdManagement.nav.title"))
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
        .alert(LocalizedStringKey("householdManagement.alert.title"), isPresented: Binding(
            get: { inviteCodeToShare != nil },
            set: { if !$0 { inviteCodeToShare = nil } }
        )) {
            Button(LocalizedStringKey("householdManagement.button.copy")) {
                if let code = inviteCodeToShare {
#if canImport(UIKit)
                    UIPasteboard.general.string = code
#endif
                }
                inviteCodeToShare = nil
            }
            Button(LocalizedStringKey("householdManagement.button.close"), role: .cancel) {
                inviteCodeToShare = nil
            }
        } message: {
            if let code = inviteCodeToShare {
                Text("householdManagement.alert.message \(inviteHouseholdName) \(code)")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            navigationContainer {
                Form {
                    TextField(LocalizedStringKey("householdManagement.field.name"), text: $draftName)
                }
                .navigationTitle(LocalizedStringKey("householdManagement.form.newTitle"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(LocalizedStringKey("common.cancel")) { showAddSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(LocalizedStringKey("householdManagement.button.create")) {
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
                    TextField(LocalizedStringKey("householdManagement.field.name"), text: $draftName)
                }
                .navigationTitle(LocalizedStringKey("householdManagement.form.renameTitle"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(LocalizedStringKey("common.cancel")) { editingHousehold = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(LocalizedStringKey("common.save")) {
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
                joinStatus = JoinStatus(message: String(localized: "householdManagement.join.success"), isError: false)
                joinCode = ""
            } else {
                let fallback = String(localized: "householdManagement.join.failure")
                joinStatus = JoinStatus(message: householdStore.error ?? fallback, isError: true)
            }
        }
    }
}

#Preview {
    HouseholdManagementView()
        .environmentObject(HouseholdStore())
}
