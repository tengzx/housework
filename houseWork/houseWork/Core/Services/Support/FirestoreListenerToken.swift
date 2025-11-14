//
//  FirestoreListenerToken.swift
//  houseWork
//
//  Wraps Firestore listener registrations in our ListenerToken protocol.
//

import Foundation
import FirebaseFirestore

final class FirestoreListenerToken: ListenerToken {
    private let registration: ListenerRegistration
    
    init(registration: ListenerRegistration) {
        self.registration = registration
    }
    
    func cancel() {
        registration.remove()
    }
    
    deinit {
        cancel()
    }
}
