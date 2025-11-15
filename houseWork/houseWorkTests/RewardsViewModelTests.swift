import XCTest
import SwiftUI
@testable import houseWork

final class RewardsViewModelTests: XCTestCase {
    
    @MainActor
    func testAvailablePointsMatchCompletedTasks() async throws {
        let context = await makeContext(completedScores: [40, 60])
        await Task.yield()
        XCTAssertEqual(context.viewModel.lifetimePoints, 100)
        XCTAssertEqual(context.viewModel.availablePoints, 100)
    }
    
    @MainActor
    func testRedeemingRewardConsumesPoints() async throws {
        let context = await makeContext(completedScores: [70])
        await Task.yield()
        guard let reward = context.rewardsStore.catalog.first else {
            XCTFail("Catalog missing reward")
            return
        }
        
        await context.viewModel.redeem(reward)
        await Task.yield()
        
        XCTAssertEqual(context.viewModel.history.count, 1)
        XCTAssertEqual(context.viewModel.availablePoints, max(0, 70 - reward.cost))
        let alertMessage = context.viewModel.activeAlert?.message ?? ""
        XCTAssertTrue(alertMessage.contains(NSLocalizedString(reward.titleKey, comment: "")))
    }
    
    @MainActor
    private func makeContext(
        completedScores: [Int],
        redemptions: [RewardRedemption] = []
    ) async -> (viewModel: RewardsViewModel, rewardsStore: RewardsStore) {
        let session = AuthSession(userId: "user-\(UUID().uuidString)", displayName: "Test User", email: "test@example.com")
        let memberId = UUID()
        let profile = UserProfile(
            id: session.userId,
            name: session.displayName ?? "Tester",
            email: session.email ?? "",
            accentColor: .blue,
            memberId: memberId.uuidString
        )
        let authStore = AuthStore(
            authService: InMemoryAuthenticationService(initialSession: session),
            profileService: InMemoryUserProfileService(seedProfiles: [session.userId: profile])
        )
        await Task.yield()
        guard let member = authStore.currentUser else {
            fatalError("Expected current user")
        }
        
        let tasks = completedScores.map { score in
            TaskItem(
                title: "Task \(score)",
                details: "",
                status: .completed,
                dueDate: Date(),
                score: score,
                roomTag: "General",
                assignedMembers: [member],
                completedAt: Date()
            )
        }
        let taskStore = TaskBoardStore(previewTasks: tasks)
        let rewardsStore = RewardsStore(
            previewCatalog: RewardItem.sampleCatalog,
            previewRedemptions: redemptions
        )
        let viewModel = RewardsViewModel(
            rewardsStore: rewardsStore,
            taskStore: taskStore,
            authStore: authStore
        )
        return (viewModel, rewardsStore)
    }
}
