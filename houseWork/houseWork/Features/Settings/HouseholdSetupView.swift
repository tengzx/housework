//
//  HouseholdSetupView.swift
//  houseWork
//
//  Prompt shown when a user has no households yet.
//

import SwiftUI

struct HouseholdSetupView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var mode: Mode = .create
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: mode == .create ? "house.fill" : "person.2.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            VStack(spacing: 8) {
                Text(mode == .create ? "Create Your Household" : "Join an Existing Household")
                    .font(.title.bold())
                Text(mode == .create ?
                     "Looks like you don't belong to a household yet. Create one to get started." :
                        "Have a code from a friend or family member? Enter it below to join their household.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            }
            
            if mode == .create {
                CreateHouseholdForm()
            } else {
                JoinHouseholdForm()
            }
            
            Picker("Mode", selection: $mode) {
                Text("Create").tag(Mode.create)
                Text("Join").tag(Mode.join)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            Spacer()
        }
        .padding()
    }
    
    enum Mode { case create, join }
}

private struct CreateHouseholdForm: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var name: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    var body: some View {
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

private struct JoinHouseholdForm: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var code: String = ""
    @State private var isJoining = false
    @State private var message: String?
    @State private var isError = false
    
    var body: some View {
        VStack(spacing: 16) {
            TextField("Invite code", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(isError ? Color.red : Color.green)
            }
            Button(action: joinHousehold) {
                if isJoining {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Text("Join Household")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isJoining || code.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal)
    }
    
    private func joinHousehold() {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return }
        isJoining = true
        message = nil
        isError = false
        Task {
            let success = await householdStore.joinHousehold(using: trimmed)
            await MainActor.run {
                isJoining = false
                if success {
                    message = "Joined household successfully."
                    isError = false
                    code = ""
                } else {
                    message = householdStore.error ?? "Unable to join household."
                    isError = true
                }
            }
        }
    }
}

#Preview {
    HouseholdSetupView()
        .environmentObject(HouseholdStore())
}
