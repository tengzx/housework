//
//  AuthStore.swift
//  houseWork
//
//  Simple in-memory authentication store for selecting the active household member.
//

import Foundation
import SwiftUI
import FirebaseAuth
import Combine

@MainActor
final class AuthStore: ObservableObject {
    @Published var currentUser: HouseholdMember?
    @Published var isLoading: Bool = true
    @Published var isProcessing: Bool = false
    @Published var authError: String?
    
    private var authListener: AuthStateDidChangeListenerHandle?
    
    init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                self.isLoading = false
                self.currentUser = user.map(Self.makeMember(from:))
            }
        }
    }
    
    deinit {
        if let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
        }
    }
    
    func signIn(email: String, password: String) async {
        await authenticate {
            try await Auth.auth().signIn(withEmail: email, password: password)
        }
    }
    
    func signUp(name: String, email: String, password: String) async {
        await authenticate {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            if let changeRequest = result.user.createProfileChangeRequest() as UserProfileChangeRequest? {
                changeRequest.displayName = name
                try await changeRequest.commitChanges()
            }
            return result
        }
    }
    
    func logout() {
        do {
            try Auth.auth().signOut()
            currentUser = nil
        } catch {
            authError = error.localizedDescription
        }
    }
    
    private func authenticate(_ action: @escaping () async throws -> AuthDataResult) async {
        isProcessing = true
        authError = nil
        do {
            let result = try await action()
            currentUser = AuthStore.makeMember(from: result.user)
        } catch {
            authError = error.localizedDescription
        }
        isProcessing = false
    }
    
    private static func makeMember(from user: User) -> HouseholdMember {
        let name = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialsSource = name?.isEmpty == false ? name! : user.email ?? "User"
        return HouseholdMember(
            name: name?.isEmpty == false ? name! : (user.email ?? "Unnamed"),
            initials: initialsSource.split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined(),
            accentColor: .blue
        )
    }
}
