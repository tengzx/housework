//
//  AuthStore.swift
//  houseWork
//
//  Simple in-memory authentication store for selecting the active household member.
//

import Foundation
import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AuthStore: ObservableObject {
    @Published var currentUser: HouseholdMember?
    @Published private(set) var userProfile: UserProfile?
    @Published private(set) var firebaseUserId: String?
    @Published private(set) var currentEmail: String?
    @Published var isLoading: Bool = true
    @Published var isProcessing: Bool = false
    @Published var authError: String?
    @Published private(set) var didProcessInitialSession: Bool = false
    
    private let authService: AuthenticationService
    private let profileService: UserProfileService
    private var authListener: ListenerToken?
    private let defaults: UserDefaults
    private let storedUserIdKey = "authStore.userId"
    private let memberUUIDKeyPrefix = "authStore.memberUUID."
    private var profileLoadIdentifier = UUID()
    
    init(
        authService: AuthenticationService = FirebaseAuthenticationService(),
        profileService: UserProfileService = FirestoreUserProfileService(),
        defaults: UserDefaults = .standard
    ) {
        self.authService = authService
        self.profileService = profileService
        self.defaults = defaults
        authListener = authService.addStateListener { [weak self] session in
            guard let self else { return }
            Task { @MainActor in
                await self.handleSessionChange(session)
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
            currentEmail = nil
            currentUser = nil
            userProfile = nil
            defaults.removeObject(forKey: storedUserIdKey)
            didProcessInitialSession = true
        } catch {
            authError = error.localizedDescription
        }
    }
    
    private func authenticate(_ action: @escaping () async throws -> AuthSession) async {
        isProcessing = true
        authError = nil
        do {
            var session = try await action()
            session = await refreshedSession(basedOn: session)
            firebaseUserId = session.userId
            currentEmail = session.email
            defaults.set(session.userId, forKey: storedUserIdKey)
            await loadProfile(for: session)
            didProcessInitialSession = true
        } catch {
            authError = error.localizedDescription
        }
        isProcessing = false
    }

#if canImport(UIKit)
    func signInWithGoogle(presenting viewController: UIViewController?) async {
        isProcessing = true
        authError = nil
        do {
            var session = try await authService.signInWithGoogle(presenting: viewController)
            session = await refreshedSession(basedOn: session)
            firebaseUserId = session.userId
            currentEmail = session.email
            defaults.set(session.userId, forKey: storedUserIdKey)
            await loadProfile(for: session)
            didProcessInitialSession = true
        } catch {
            authError = error.localizedDescription
        }
        isProcessing = false
    }
#endif
    
    private func handleSessionChange(_ session: AuthSession?) async {
        isLoading = false
        guard let session else {
            firebaseUserId = nil
            currentEmail = nil
            currentUser = nil
            userProfile = nil
            defaults.removeObject(forKey: storedUserIdKey)
            didProcessInitialSession = true
            return
        }
        let resolved = await refreshedSession(basedOn: session)
        firebaseUserId = resolved.userId
        currentEmail = resolved.email
        await loadProfile(for: resolved)
        didProcessInitialSession = true
    }
    
    @discardableResult
    func updateProfile(name: String, accentColor: Color) async -> Bool {
        guard let userId = firebaseUserId else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        let identifier = memberIdentifier(for: userId, prefer: userProfile?.memberUUID)
        var profile = userProfile ?? UserProfile(
            id: userId,
            name: trimmedName,
            email: currentEmail ?? "",
            accentColor: accentColor,
            memberId: identifier.uuidString,
            points: 0
        )
        profile.name = trimmedName
        profile.accentColor = accentColor
        profile.memberId = identifier.uuidString
        profile.points = userProfile?.points ?? profile.points
        do {
            try await profileService.saveProfile(profile)
            try? await authService.updateDisplayName(trimmedName)
            apply(profile: profile, userId: userId)
            profileLoadIdentifier = UUID()
            authError = nil
            return true
        } catch {
            authError = error.localizedDescription
            return false
        }
    }
    
    private func loadProfile(for session: AuthSession) async {
        let loadID = UUID()
        profileLoadIdentifier = loadID
        let fallback = defaultProfile(for: session)
        do {
            if var existing = try await profileService.loadProfile(userId: session.userId) {
                var requiresSave = false
                if existing.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let displayName = session.displayName, !displayName.isEmpty {
                    existing.name = displayName
                    requiresSave = true
                }
                if existing.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let email = session.email {
                    existing.email = email
                    requiresSave = true
                }
                let identifier = memberIdentifier(for: session.userId, prefer: existing.memberUUID)
                if existing.memberUUID == nil {
                    existing.memberId = identifier.uuidString
                    requiresSave = true
                }
                if let photo = session.photoURL {
                    let previous = existing.avatarURL?.absoluteString
                    if previous != photo.absoluteString {
                        existing.avatarURL = photo
                        requiresSave = true
                    }
                }
                if requiresSave {
                    try await profileService.saveProfile(existing)
                }
                guard loadID == profileLoadIdentifier else { return }
                apply(profile: existing, userId: session.userId)
            } else {
                try await profileService.saveProfile(fallback)
                guard loadID == profileLoadIdentifier else { return }
                apply(profile: fallback, userId: session.userId)
            }
        } catch {
            authError = error.localizedDescription
            guard loadID == profileLoadIdentifier else { return }
            if userProfile == nil {
                apply(profile: fallback, userId: session.userId)
            }
            return
        }
        if loadID == profileLoadIdentifier {
            authError = nil
        }
    }
    
    private func defaultProfile(for session: AuthSession) -> UserProfile {
        let displayName = session.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = displayName?.isEmpty == false ? displayName! : (session.email ?? "Unnamed")
        let email = session.email ?? ""
        let colors = HouseholdMember.defaultAvatarColors
        let colorIndex = abs(session.userId.hashValue) % max(colors.count, 1)
        let selectedColor = colors[colorIndex]
        let identifier = memberIdentifier(for: session.userId)
        return UserProfile(id: session.userId, name: name, email: email, accentColor: selectedColor, memberId: identifier.uuidString, avatarURL: session.photoURL, points: 0)
    }
    
    private func refreshedSession(basedOn session: AuthSession) async -> AuthSession {
        guard let refreshed = await authService.refreshCurrentSession(), refreshed.userId == session.userId else {
            return session
        }
        return refreshed
    }
    
    private func apply(profile: UserProfile, userId: String) {
        var resolvedProfile = profile
        let identifier = memberIdentifier(for: userId, prefer: profile.memberUUID)
        if resolvedProfile.memberUUID == nil {
            resolvedProfile.memberId = identifier.uuidString
        }
        userProfile = resolvedProfile
        currentUser = resolvedProfile.asHouseholdMember(fallbackId: identifier)
    }
    
    private func memberIdentifier(for userId: String, prefer preferred: UUID? = nil) -> UUID {
        let key = memberUUIDKeyPrefix + userId
        if let cached = defaults.string(forKey: key), let uuid = UUID(uuidString: cached) {
            return uuid
        }
        if let preferred {
            defaults.set(preferred.uuidString, forKey: key)
            return preferred
        }
        let newValue = UUID()
        defaults.set(newValue.uuidString, forKey: key)
        return newValue
    }
    
    @discardableResult
    func adjustPoints(by delta: Int) async -> Bool {
        guard delta != 0 else { return true }
        guard var profile = userProfile else { return false }
        guard let userId = firebaseUserId else { return false }
        let current = profile.points
        let updated = max(0, current + delta)
        profile.points = updated
        do {
            try await profileService.saveProfile(profile)
            apply(profile: profile, userId: userId)
            return true
        } catch {
            authError = error.localizedDescription
            return false
        }
    }
}
