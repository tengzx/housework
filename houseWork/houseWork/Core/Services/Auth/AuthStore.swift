//
//  AuthStore.swift
//  houseWork
//
//  Simple in-memory authentication store for selecting the active household member.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AuthStore: ObservableObject {
    @Published var currentUser: HouseholdMember?
    @Published private(set) var firebaseUserId: String?
    @Published var isLoading: Bool = true
    @Published var isProcessing: Bool = false
    @Published var authError: String?
    
    private let authService: AuthenticationService
    private var authListener: ListenerToken?
    private let defaults: UserDefaults
    private let storedUserIdKey = "authStore.userId"
    private let memberUUIDKeyPrefix = "authStore.memberUUID."
    
    init(
        authService: AuthenticationService = FirebaseAuthenticationService(),
        defaults: UserDefaults = .standard
    ) {
        self.authService = authService
        self.defaults = defaults
        authListener = authService.addStateListener { [weak self] session in
            guard let self else { return }
            Task { @MainActor in
                self.handleSessionChange(session)
            }
        }
    }
    
    deinit {
        if let authListener {
            authListener.cancel()
        }
    }
    
    func signIn(email: String, password: String) async {
        await authenticate { [authService = self.authService] in
            try await authService.signIn(email: email, password: password)
        }
    }
    
    func signUp(name: String, email: String, password: String) async {
        await authenticate { [authService = self.authService] in
            try await authService.signUp(name: name, email: email, password: password)
        }
    }
    
    func logout() {
        do {
            try authService.signOut()
            firebaseUserId = nil
            currentUser = nil
            defaults.removeObject(forKey: storedUserIdKey)
        } catch {
            authError = error.localizedDescription
        }
    }
    
    private func authenticate(_ action: @escaping () async throws -> AuthSession) async {
        isProcessing = true
        authError = nil
        do {
            let session = try await action()
            firebaseUserId = session.userId
            currentUser = makeMember(from: session)
            defaults.set(session.userId, forKey: storedUserIdKey)
        } catch {
            authError = error.localizedDescription
        }
        isProcessing = false
    }
    
    private func handleSessionChange(_ session: AuthSession?) {
        isLoading = false
        guard let session else {
            firebaseUserId = nil
            currentUser = nil
            defaults.removeObject(forKey: storedUserIdKey)
            return
        }
        firebaseUserId = session.userId
        currentUser = makeMember(from: session)
    }
    
    private func makeMember(from session: AuthSession) -> HouseholdMember {
        let displayName = session.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialsSource = displayName?.isEmpty == false ? displayName! : (session.email ?? "User")
        let memberId = memberIdentifier(for: session.userId)
        return HouseholdMember(
            id: memberId,
            name: displayName?.isEmpty == false ? displayName! : (session.email ?? "Unnamed"),
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
