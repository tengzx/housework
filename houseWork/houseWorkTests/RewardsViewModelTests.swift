import XCTest
import SwiftUI
@testable import houseWork

final class RewardsViewModelTests: XCTestCase {
    
    @MainActor
    func testAvailablePointsReflectProfilePoints() async throws {
        let context = await makeContext(initialPoints: 150)
        await Task.yield()
        XCTAssertEqual(context.viewModel.availablePoints, 150)
        XCTAssertEqual(context.viewModel.lifetimePoints, 150)
    }
    
    @MainActor
    func testRedeemingRewardConsumesPoints() async throws {
        let context = await makeContext(initialPoints: 200)
        await Task.yield()
        guard let reward = context.rewardsStore.catalog.first else {
            XCTFail("Catalog missing reward")
            return
        }
        
        await context.viewModel.redeem(reward)
        await Task.yield()
        
        XCTAssertEqual(context.viewModel.history.count, 1)
        XCTAssertEqual(context.viewModel.availablePoints, 200 - reward.cost)
        XCTAssertEqual(context.authStore.userProfile?.points, 200 - reward.cost)
    }
    
    @MainActor
    private func makeContext(
        initialPoints: Int,
        redemptions: [RewardRedemption] = []
    ) async -> (viewModel: RewardsViewModel, rewardsStore: RewardsStore, authStore: AuthStore) {
        let session = AuthSession(userId: "user-\(UUID().uuidString)", displayName: "Test User", email: "test@example.com")
        let memberId = UUID()
        let profile = UserProfile(
            id: session.userId,
            name: session.displayName ?? "Tester",
            email: session.email ?? "",
            accentColor: .blue,
            memberId: memberId.uuidString,
            points: initialPoints
        )
        let authStore = AuthStore(
            authService: InMemoryAuthenticationService(initialSession: session),
            profileService: InMemoryUserProfileService(seedProfiles: [session.userId: profile])
        )
        await Task.yield()
        guard let member = authStore.currentUser else {
            fatalError("Expected current user")
        }
        let rewardsStore = RewardsStore(
            previewCatalog: RewardItem.sampleCatalog,
            previewRedemptions: redemptions
        )
        let viewModel = RewardsViewModel(
            rewardsStore: rewardsStore,
            authStore: authStore
        )
        return (viewModel, rewardsStore, authStore)
    }
}
