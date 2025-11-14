//
//  LoginViewModel.swift
//  houseWork
//
//  Handles login / sign-up form state and delegates to AuthStore.
//

import Foundation
import Combine

@MainActor
final class LoginViewModel: ObservableObject {
    enum Mode {
        case signIn
        case signUp
    }
    
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var fullName: String = ""
    @Published var mode: Mode = .signIn
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var errorMessage: String?
    
    private let authStore: AuthStore
    private var cancellables: Set<AnyCancellable> = []
    
    init(authStore: AuthStore) {
        self.authStore = authStore
        bind()
    }
    
    var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        (mode == .signIn || !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    
    func performPrimaryAction() async {
        guard isFormValid else { return }
        switch mode {
        case .signIn:
            await authStore.signIn(email: trimmedEmail, password: password)
        case .signUp:
            await authStore.signUp(name: trimmedFullName, email: trimmedEmail, password: password)
        }
    }
    
    func toggleMode() {
        mode = (mode == .signIn) ? .signUp : .signIn
        authStore.authError = nil
        errorMessage = nil
    }
    
    private func bind() {
        authStore.$isProcessing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isProcessing)
        
        authStore.$authError
            .receive(on: DispatchQueue.main)
            .assign(to: &$errorMessage)
    }
    
    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    private var trimmedFullName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
