//
//  HouseholdSetupView.swift
//  houseWork
//
//  Prompt shown when a user has no households yet.
//

import SwiftUI

struct HouseholdSetupView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var name: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "house.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            VStack(spacing: 8) {
                Text("Create Your Household")
                    .font(.title.bold())
                Text("Looks like you don't belong to a household yet. Create one to get started.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 16) {
                TextField("Household name", text: $name)
                    .textFieldStyle(.roundedBorder)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button(action: createHousehold) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Create Household")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
    
    private func createHousehold() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true
        errorMessage = nil
        let trimmed = name
        Task {
            let success = await householdStore.createHousehold(named: trimmed)
            await MainActor.run {
                isSaving = false
                if !success {
                    errorMessage = householdStore.error ?? "Unable to create household."
                }
            }
        }
    }
}

#Preview {
    HouseholdSetupView()
        .environmentObject(HouseholdStore())
}
