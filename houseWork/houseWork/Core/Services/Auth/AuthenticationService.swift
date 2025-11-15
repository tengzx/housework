//
//  AuthenticationService.swift
//  houseWork
//
//  Abstracts Firebase Auth to improve testability.
//

import Foundation
import FirebaseAuth
import FirebaseCore
#if canImport(UIKit)
import UIKit
#endif

struct AuthSession {
    let userId: String
    let displayName: String?
    let email: String?
    let photoURL: URL?
    
    init(userId: String, displayName: String?, email: String?, photoURL: URL? = nil) {
        self.userId = userId
        self.displayName = displayName
        self.email = email
        self.photoURL = photoURL
    }
}

protocol AuthenticationService {
    func addStateListener(_ handler: @escaping (AuthSession?) -> Void) -> ListenerToken
    func signIn(email: String, password: String) async throws -> AuthSession
    func signUp(name: String, email: String, password: String) async throws -> AuthSession
    func signOut() throws
    func updateDisplayName(_ name: String) async throws
    func signInWithGoogle(presenting viewController: UIViewController?) async throws -> AuthSession
    func refreshCurrentSession() async -> AuthSession?
}

final class FirebaseAuthenticationService: AuthenticationService {
    private let auth: Auth
    
    init(auth: Auth = Auth.auth()) {
        self.auth = auth
    }
    
    func addStateListener(_ handler: @escaping (AuthSession?) -> Void) -> ListenerToken {
        let handle = auth.addStateDidChangeListener { _, user in
            handler(user.map(AuthSession.init))
        }
        return FirebaseAuthListenerToken(auth: auth, handle: handle)
    }
    
    func signIn(email: String, password: String) async throws -> AuthSession {
        let result = try await auth.signIn(withEmail: email, password: password)
        return AuthSession(user: result.user)
    }
    
    func signUp(name: String, email: String, password: String) async throws -> AuthSession {
        let result = try await auth.createUser(withEmail: email, password: password)
        if let changeRequest = result.user.createProfileChangeRequest() as UserProfileChangeRequest? {
            changeRequest.displayName = name
            try await changeRequest.commitChanges()
        }
        return AuthSession(user: result.user)
    }
    
    func signOut() throws {
        try auth.signOut()
#if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
#endif
    }
    
    func updateDisplayName(_ name: String) async throws {
        guard let user = auth.currentUser else { return }
        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = name
        try await changeRequest.commitChanges()
    }

    func signInWithGoogle(presenting viewController: UIViewController?) async throws -> AuthSession {
#if os(iOS)
        let provider = OAuthProvider(providerID: "google.com", auth: auth)
        provider.scopes = ["profile", "email"]
        provider.customParameters = ["prompt": "select_account"]
        let credential = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthCredential, Error>) in
            provider.getCredentialWith(nil) { credential, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let credential else {
                    continuation.resume(throwing: AuthenticationServiceError.missingCredential)
                    return
                }
                continuation.resume(returning: credential)
            }
        }
        let authResult = try await auth.signIn(with: credential)
        return AuthSession(user: authResult.user)
#else
        throw AuthenticationServiceError.googleSignInUnavailable
#endif
    }
    
    func refreshCurrentSession() async -> AuthSession? {
        guard let user = auth.currentUser else { return nil }
        do {
            try await user.reload()
        } catch {
            // Ignore reload errors and fall back to the last known snapshot.
        }
        return AuthSession(user: user)
    }
}

private final class FirebaseAuthListenerToken: ListenerToken {
    private weak var auth: Auth?
    private let handle: AuthStateDidChangeListenerHandle
    
    init(auth: Auth, handle: AuthStateDidChangeListenerHandle) {
        self.auth = auth
        self.handle = handle
    }
    
    func cancel() {
        if let auth {
            auth.removeStateDidChangeListener(handle)
        }
    }
    
    deinit {
        cancel()
    }
}

extension AuthSession {
    init(user: User) {
        let googlePhoto = user.providerData
            .first(where: { $0.providerID == "google.com" })?
            .photoURL
        self.userId = user.uid
        self.displayName = user.displayName
        self.email = user.email
        self.photoURL = googlePhoto ?? user.photoURL
    }
}

final class InMemoryAuthenticationService: AuthenticationService {
    enum AuthError: Error {
        case invalidCredentials
    }
    
    private var currentSession: AuthSession? {
        didSet { notifyListeners() }
    }
    private var listeners: [UUID: (AuthSession?) -> Void] = [:]
    private var credentials: [String: (password: String, displayName: String?)] = [:]
    
    init(initialSession: AuthSession? = nil) {
        self.currentSession = initialSession
    }
    
    func addStateListener(_ handler: @escaping (AuthSession?) -> Void) -> ListenerToken {
        let id = UUID()
        listeners[id] = handler
        handler(currentSession)
        return BlockListenerToken { [weak self] in
            self?.listeners.removeValue(forKey: id)
        }
    }
    
    func signIn(email: String, password: String) async throws -> AuthSession {
        guard let stored = credentials[email.lowercased()], stored.password == password else {
            throw AuthError.invalidCredentials
        }
        let session = AuthSession(userId: UUID().uuidString, displayName: stored.displayName, email: email, photoURL: nil)
        currentSession = session
        return session
    }
    
    func signUp(name: String, email: String, password: String) async throws -> AuthSession {
        credentials[email.lowercased()] = (password, name)
        let session = AuthSession(userId: UUID().uuidString, displayName: name, email: email, photoURL: nil)
        currentSession = session
        return session
    }
    
    func signOut() throws {
        currentSession = nil
    }
    
    func updateDisplayName(_ name: String) async throws {
        guard let session = currentSession else { return }
        currentSession = AuthSession(userId: session.userId, displayName: name, email: session.email, photoURL: session.photoURL)
    }

#if canImport(UIKit)
    func signInWithGoogle(presenting viewController: UIViewController?) async throws -> AuthSession {
        let session = AuthSession(
            userId: UUID().uuidString,
            displayName: "Google User",
            email: "google-user@example.com",
            photoURL: nil
        )
        currentSession = session
        return session
    }
#endif
    
    func refreshCurrentSession() async -> AuthSession? {
        currentSession
    }
    
    private func notifyListeners() {
        listeners.values.forEach { $0(currentSession) }
    }
}

enum AuthenticationServiceError: LocalizedError {
    case missingClientID
    case missingPresentingController
    case missingIDToken
    case googleSignInUnavailable
    case missingCredential
    
    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Missing Google client configuration."
        case .missingPresentingController:
            return "Unable to present Google sign-in."
        case .missingIDToken:
            return "Google sign-in did not return a valid token."
        case .googleSignInUnavailable:
            return "Google sign-in is not available on this platform."
        case .missingCredential:
            return "Unable to obtain Google credentials."
        }
    }
}
