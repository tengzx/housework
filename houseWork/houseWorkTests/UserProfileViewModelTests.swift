import XCTest
import SwiftUI
@testable import houseWork

final class UserProfileViewModelTests: XCTestCase {
    
    @MainActor
    func testSaveUpdatesProfile() async throws {
        let session = AuthSession(userId: "user-1", displayName: "Old Name", email: "test@example.com")
        let authService = InMemoryAuthenticationService(initialSession: session)
        let initialProfile = UserProfile(id: session.userId, name: "Old Name", email: "test@example.com", accentColor: .blue, memberId: UUID().uuidString)
        let profileService = InMemoryUserProfileService(seedProfiles: [session.userId: initialProfile])
        let authStore = AuthStore(authService: authService, profileService: profileService)
        let viewModel = UserProfileViewModel(authStore: authStore)
        await Task.yield()
        
        viewModel.name = "Updated Name"
        viewModel.selectedColor = .green
        
        let success = await viewModel.save()
        
        XCTAssertTrue(success)
        XCTAssertEqual(authStore.userProfile?.name, "Updated Name")
        XCTAssertEqual(profileService.profile(for: session.userId)?.accentColor.hexString, Color.green.hexString)
    }
}
