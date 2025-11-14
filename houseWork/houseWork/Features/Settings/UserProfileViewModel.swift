//
//  UserProfileViewModel.swift
//  houseWork
//
//  Handles editing + saving the signed-in user's profile details.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class UserProfileViewModel: ObservableObject {
    @Published var name: String
    @Published var selectedColor: Color
    @Published private(set) var email: String
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    
    let colorOptions: [Color] = HouseholdMember.defaultAvatarColors
    
    private let authStore: AuthStore
    private var cancellables: Set<AnyCancellable> = []
    
    init(authStore: AuthStore) {
        self.authStore = authStore
        let profile = authStore.userProfile
        self.name = profile?.name ?? authStore.currentUser?.name ?? ""
        self.selectedColor = profile?.accentColor ?? authStore.currentUser?.accentColor ?? .blue
        self.email = profile?.email ?? authStore.currentEmail ?? ""
        bind()
    }
    
    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }
    
    func save() async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "userProfile.error.emptyName")
            return false
        }
        isSaving = true
        errorMessage = nil
        let success = await authStore.updateProfile(name: trimmed, accentColor: selectedColor)
        isSaving = false
        if !success {
            errorMessage = authStore.authError ?? String(localized: "userProfile.error.saveFailed")
        }
        return success
    }
    
    private func bind() {
        authStore.$userProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                guard let self, let profile else { return }
                self.name = profile.name
                self.email = profile.email
                self.selectedColor = profile.accentColor
            }
            .store(in: &cancellables)
        
        authStore.$currentEmail
            .receive(on: DispatchQueue.main)
            .sink { [weak self] email in
                guard let self, let email else { return }
                self.email = email
            }
            .store(in: &cancellables)
    }
}
