import XCTest
@testable import houseWork

final class TaskBoardViewModelTests: XCTestCase {
    
    @MainActor
    func testMineFilterShowsOnlyAssignedTasks() async throws {
        let session = AuthSession(userId: "user-1", displayName: "Test User", email: "test@example.com")
        let authService = InMemoryAuthenticationService(initialSession: session)
        let authStore = AuthStore(authService: authService)
        let householdSummary = HouseholdSummary(id: "house-1", name: "Test Home", inviteCode: "ABC123")
        let householdService = InMemoryHouseholdService(
            seedHouseholds: [householdSummary],
            membership: ["user-1": ["house-1"]]
        )
        let householdStore = HouseholdStore(service: householdService)
        householdStore.updateUserContext(userId: "user-1", force: true)
        let tagStore = TagStore(householdStore: householdStore, service: InMemoryTagService())
        
        guard let currentUser = authStore.currentUser else {
            XCTFail("Expected current user to be set")
            return
        }
        
        let ownTask = TaskItem(
            title: "My Task",
            details: "Do something important",
            status: .backlog,
            dueDate: Date(),
            score: 10,
            roomTag: "General",
            assignedMembers: [currentUser]
        )
        let otherTask = TaskItem(
            title: "Other Task",
            details: "Somebody else's work",
            status: .backlog,
            dueDate: Date(),
            score: 5,
            roomTag: "General",
            assignedMembers: []
        )
        let taskStore = TaskBoardStore(previewTasks: [ownTask, otherTask])
        let viewModel = TaskBoardViewModel(
            taskStore: taskStore,
            authStore: authStore,
            householdStore: householdStore,
            tagStore: tagStore
        )
        
        XCTAssertEqual(viewModel.filteredTasks.count, 2)
        
        viewModel.selectedFilter = .mine
        
        XCTAssertEqual(viewModel.filteredTasks.count, 1)
        XCTAssertEqual(viewModel.filteredTasks.first?.title, "My Task")
    }
}
