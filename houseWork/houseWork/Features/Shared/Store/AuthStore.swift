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
    @Published private(set) var firebaseUserId: String?
    @Published var isLoading: Bool = true
    @Published var isProcessing: Bool = false
    @Published var authError: String?
    
    private var authListener: AuthStateDidChangeListenerHandle?
    private let defaults = UserDefaults.standard
    private let storedUserIdKey = "authStore.userId"
    private let memberUUIDKeyPrefix = "authStore.memberUUID."
    
    init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                self.isLoading = false
                if let user {
                    self.firebaseUserId = user.uid
                    self.currentUser = self.makeMember(from: user)
                } else {
                    self.firebaseUserId = nil
                    self.currentUser = nil
                    self.defaults.removeObject(forKey: self.storedUserIdKey)
                }
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
            firebaseUserId = nil
            currentUser = nil
            defaults.removeObject(forKey: storedUserIdKey)
        } catch {
            authError = error.localizedDescription
        }
    }
    
    private func authenticate(_ action: @escaping () async throws -> AuthDataResult) async {
        isProcessing = true
        authError = nil
        do {
            let result = try await action()
            firebaseUserId = result.user.uid
            currentUser = makeMember(from: result.user)
            defaults.set(result.user.uid, forKey: storedUserIdKey)
        } catch {
            authError = error.localizedDescription
        }
        isProcessing = false
    }
    
    private func makeMember(from user: User) -> HouseholdMember {
        let name = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialsSource = name?.isEmpty == false ? name! : user.email ?? "User"
        let memberId = memberIdentifier(for: user.uid)
        return HouseholdMember(
            id: memberId,
            name: name?.isEmpty == false ? name! : (user.email ?? "Unnamed"),
            initials: initialsSource.split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined(),
            accentColor: .blue
        )
    }
    
    private func memberIdentifier(for userId: String) -> UUID {
        let key = memberUUIDKeyPrefix + userId
        if let cached = defaults.string(forKey: key), let uuid = UUID(uuidString: cached) {
            return uuid
        }
        let newValue = UUID()
        defaults.set(newValue.uuidString, forKey: key)
        return newValue
    }
}
