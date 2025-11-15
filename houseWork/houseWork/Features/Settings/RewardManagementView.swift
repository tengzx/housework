//
//  RewardManagementView.swift
//  houseWork
//
//  Allows household admins to manage redeemable rewards.
//

import SwiftUI

struct RewardManagementView: View {
    @EnvironmentObject private var rewardsStore: RewardsStore
    @State private var showingForm = false
    @State private var nameDraft: String = ""
    @State private var costDraft: String = ""
    @State private var formError: String?
    
    var body: some View {
        navigationContainer {
            List {
                if rewardsStore.catalog.isEmpty {
                    Text(LocalizedStringKey("rewards.management.empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(rewardsStore.catalog) { reward in
                        HStack {
                            Text(reward.name)
                            Spacer()
                            Text(String(format: String(localized: "rewards.cost.format"), reward.cost))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteRewards)
                }
            }
            .navigationTitle(LocalizedStringKey("rewards.management.title"))
            .toolbar {
                Button {
                    Haptics.impact()
                    nameDraft = ""
                    costDraft = ""
                    showingForm = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingForm) {
            navigationContainer {
                RewardEditorView(
                    name: $nameDraft,
                    cost: $costDraft,
                    errorMessage: $formError,
                    onSave: { name, cost in
                        Haptics.impact()
                        Task {
                            let success = await rewardsStore.addReward(name: name, cost: cost)
                            await MainActor.run {
                                if success {
                                    showingForm = false
                                    formError = nil
                                } else {
                                    formError = String(localized: "rewards.management.error.save")
                                }
                            }
                        }
                    }
                )
            }
        }
        .alert(
            LocalizedStringKey("rewards.alert.error"),
            isPresented: Binding(
                get: { formError != nil },
                set: { if !$0 { formError = nil } }
            ),
            actions: {
                Button(LocalizedStringKey("common.ok"), role: .cancel) { }
            },
            message: {
                Text(formError ?? "")
            }
        )
    }
    
    private func deleteRewards(at offsets: IndexSet) {
        Haptics.impact()
        for index in offsets {
            guard rewardsStore.catalog.indices.contains(index) else { continue }
            let reward = rewardsStore.catalog[index]
            Task {
                _ = await rewardsStore.deleteReward(reward)
            }
        }
    }
}

private struct RewardEditorView: View {
    @Binding var name: String
    @Binding var cost: String
    @Binding var errorMessage: String?
    let onSave: (String, Int) -> Void
    
    var body: some View {
        Form {
            Section {
                TextField(LocalizedStringKey("rewards.management.field.name"), text: $name)
                    .textInputAutocapitalization(.words)
                TextField(LocalizedStringKey("rewards.management.field.cost"), text: $cost)
                    .keyboardType(.numberPad)
            }
            Section {
                Button {
                    Haptics.impact()
                    guard let points = Int(cost), points > 0 else {
                        errorMessage = String(localized: "rewards.management.error.invalid")
                        return
                    }
                    onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), points)
                } label: {
                    Text(LocalizedStringKey("common.save"))
                        .frame(maxWidth: .infinity)
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (Int(cost) ?? 0) <= 0)
            }
        }
        .navigationTitle(LocalizedStringKey("rewards.management.form.title"))
    }
}
