//
//  AuthenticationService.swift
//  houseWork
//
//  Abstracts Firebase Auth to improve testability.
//

import Foundation
import FirebaseAuth

struct AuthSession {
    let userId: String
    let displayName: String?
    let email: String?
}

protocol AuthenticationService {
    func addStateListener(_ handler: @escaping (AuthSession?) -> Void) -> ListenerToken
    func signIn(email: String, password: String) async throws -> AuthSession
    func signUp(name: String, email: String, password: String) async throws -> AuthSession
    func signOut() throws
    func updateDisplayName(_ name: String) async throws
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
    }
    
    func updateDisplayName(_ name: String) async throws {
        guard let user = auth.currentUser else { return }
        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = name
        try await changeRequest.commitChanges()
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
        self.userId = user.uid
        self.displayName = user.displayName
        self.email = user.email
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
        let session = AuthSession(userId: UUID().uuidString, displayName: stored.displayName, email: email)
        currentSession = session
        return session
    }
    
    func signUp(name: String, email: String, password: String) async throws -> AuthSession {
        credentials[email.lowercased()] = (password, name)
        let session = AuthSession(userId: UUID().uuidString, displayName: name, email: email)
        currentSession = session
        return session
    }
    
    func signOut() throws {
        currentSession = nil
    }
    
    func updateDisplayName(_ name: String) async throws {
        guard let session = currentSession else { return }
        currentSession = AuthSession(userId: session.userId, displayName: name, email: session.email)
    }
    
    private func notifyListeners() {
        listeners.values.forEach { $0(currentSession) }
    }
}
