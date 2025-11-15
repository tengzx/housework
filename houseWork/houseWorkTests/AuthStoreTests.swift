import XCTest
import SwiftUI
@testable import houseWork
#if canImport(UIKit)
import UIKit
#endif

final class AuthStoreTests: XCTestCase {
    
    @MainActor
    func testUpdatesAvatarWhenRefreshedSessionHasNewPhoto() async throws {
        let userId = "user-123"
        let initialAvatar = URL(string: "https://example.com/old.png")!
        let updatedAvatar = URL(string: "https://example.com/new.png")!
        let profile = UserProfile(
            id: userId,
            name: "Taylor",
            email: "taylor@example.com",
            accentColor: .blue,
            memberId: UUID().uuidString,
            avatarURL: initialAvatar
        )
        let profileService = InMemoryUserProfileService(seedProfiles: [userId: profile])
        let initialSession = AuthSession(
            userId: userId,
            displayName: profile.name,
            email: profile.email,
            photoURL: initialAvatar
        )
        let refreshedSession = AuthSession(
            userId: userId,
            displayName: profile.name,
            email: profile.email,
            photoURL: updatedAvatar
        )
        let authService = MockAuthenticationService(initialSession: initialSession, refreshedSession: refreshedSession)
        let store = AuthStore(authService: authService, profileService: profileService)
        
        await Task.yield()
        
        XCTAssertEqual(profileService.profile(for: userId)?.avatarURL, updatedAvatar)
        XCTAssertEqual(store.userProfile?.avatarURL, updatedAvatar)
    }
}

private final class MockAuthenticationService: AuthenticationService {
    private let initialSession: AuthSession?
    private let refreshedSession: AuthSession?
    
    init(initialSession: AuthSession?, refreshedSession: AuthSession?) {
        self.initialSession = initialSession
        self.refreshedSession = refreshedSession
    }
    
    func addStateListener(_ handler: @escaping (AuthSession?) -> Void) -> ListenerToken {
        handler(initialSession)
        return BlockListenerToken {}
    }
    
    func signIn(email: String, password: String) async throws -> AuthSession {
        fatalError("Not implemented")
    }
    
    func signUp(name: String, email: String, password: String) async throws -> AuthSession {
        fatalError("Not implemented")
    }
    
    func signOut() throws {}
    
    func updateDisplayName(_ name: String) async throws {}
    
#if canImport(UIKit)
    func signInWithGoogle(presenting viewController: UIViewController?) async throws -> AuthSession {
        fatalError("Not implemented")
    }
#endif
    
    func refreshCurrentSession() async -> AuthSession? {
        refreshedSession
    }
}
