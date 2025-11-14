//
//  UserProfileService.swift
//  houseWork
//
//  Persists user profile metadata (display name, avatar color) via Firebase.
//

import Foundation
import FirebaseFirestore
import SwiftUI

protocol UserProfileService {
    func loadProfile(userId: String) async throws -> UserProfile?
    func saveProfile(_ profile: UserProfile) async throws
    func observeProfiles(_ handler: @escaping (Result<[UserProfile], Error>) -> Void) -> ListenerToken
}

enum UserProfileServiceError: LocalizedError {
    case userNotFound
    
    var errorDescription: String? {
        switch self {
        case .userNotFound:
            return "Unable to load user profile."
        }
    }
}

final class FirestoreUserProfileService: UserProfileService {
    private let db: Firestore
    
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }
    
    func loadProfile(userId: String) async throws -> UserProfile? {
        let snapshot = try await db.collection("users").document(userId).getDocument()
        guard let data = snapshot.data() else { return nil }
        return UserProfile(id: userId, data: data)
    }
    
    func saveProfile(_ profile: UserProfile) async throws {
        try await db.collection("users").document(profile.id).setData(profile.firestoreData, merge: true)
    }
    
    func observeProfiles(_ handler: @escaping (Result<[UserProfile], Error>) -> Void) -> ListenerToken {
        let registration = db.collection("users")
            .addSnapshotListener { snapshot, error in
                if let error {
                    handler(.failure(error))
                    return
                }
                guard let documents = snapshot?.documents else {
                    handler(.success([]))
                    return
                }
                let profiles = documents.compactMap { doc -> UserProfile? in
                    UserProfile(id: doc.documentID, data: doc.data())
                }
                handler(.success(profiles))
            }
        return FirestoreListenerToken(registration: registration)
    }
}

final class InMemoryUserProfileService: UserProfileService {
    private var storage: [String: UserProfile]
    
    init(seedProfiles: [String: UserProfile] = [:]) {
        self.storage = seedProfiles
    }
    
    func loadProfile(userId: String) async throws -> UserProfile? {
        storage[userId]
    }
    
    func saveProfile(_ profile: UserProfile) async throws {
        storage[profile.id] = profile
        notifyListeners()
    }
    
    func observeProfiles(_ handler: @escaping (Result<[UserProfile], Error>) -> Void) -> ListenerToken {
        let id = UUID()
        listeners[id] = handler
        handler(.success(Array(storage.values)))
        return BlockListenerToken { [weak self] in
            self?.listeners.removeValue(forKey: id)
        }
    }
    
    private var listeners: [UUID: (Result<[UserProfile], Error>) -> Void] = [:]
    
    private func notifyListeners() {
        let snapshot = Array(storage.values)
        listeners.values.forEach { $0(.success(snapshot)) }
    }
    
    func profile(for userId: String) -> UserProfile? {
        storage[userId]
    }
}
