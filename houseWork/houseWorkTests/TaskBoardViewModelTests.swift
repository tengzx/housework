import XCTest
import SwiftUI
@testable import houseWork

final class TaskBoardViewModelTests: XCTestCase {
    
    @MainActor
    func testMineFilterShowsOnlyAssignedTasks() async throws {
        let session = AuthSession(userId: "user-1", displayName: "Test User", email: "test@example.com")
        let authService = InMemoryAuthenticationService(initialSession: session)
        let profile = UserProfile(id: session.userId, name: "Test User", email: session.email ?? "", accentColor: .blue, memberId: UUID().uuidString)
        let profileService = InMemoryUserProfileService(seedProfiles: [session.userId: profile])
        let authStore = AuthStore(authService: authService, profileService: profileService)
        let householdSummary = HouseholdSummary(id: "house-1", name: "Test Home", inviteCode: "ABC123")
        let householdService = InMemoryHouseholdService(
            seedHouseholds: [householdSummary],
            membership: ["user-1": ["house-1"]]
        )
        let householdStore = HouseholdStore(service: householdService)
        householdStore.updateUserContext(userId: "user-1", force: true)
        let tagStore = TagStore(householdStore: householdStore, service: InMemoryTagService())
        
        await Task.yield()
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
        let memberDirectory = MemberDirectory(profileService: InMemoryUserProfileService(seedProfiles: [session.userId: profile]))
        let viewModel = TaskBoardViewModel(
            taskStore: taskStore,
            authStore: authStore,
            householdStore: householdStore,
            tagStore: tagStore,
            memberDirectory: memberDirectory
        )
        
        XCTAssertEqual(viewModel.filteredTasks.count, 2)
        
        viewModel.selectedFilter = .mine
        
        XCTAssertEqual(viewModel.filteredTasks.count, 1)
        XCTAssertEqual(viewModel.filteredTasks.first?.title, "My Task")
    }
    
    @MainActor
    func testShowNextWeekKeepsSelectionUntouched() {
        let viewModel = makeViewModel()
        let reference = referenceDate(year: 2024, month: 3, day: 4)
        viewModel.selectDate(reference)
        let initialWeekStart = viewModel.calendarStartOfWeek
        
        viewModel.showNextWeek()
        
        XCTAssertTrue(Calendar.current.isDate(viewModel.selectedDate, inSameDayAs: reference))
        let expectedWeekStart = Calendar.current.date(byAdding: .day, value: 7, to: initialWeekStart)!
        XCTAssertTrue(Calendar.current.isDate(viewModel.calendarStartOfWeek, inSameDayAs: expectedWeekStart))
    }
    
    @MainActor
    func testShowPreviousWeekKeepsSelectionUntouched() {
        let viewModel = makeViewModel()
        let reference = referenceDate(year: 2024, month: 3, day: 6)
        viewModel.selectDate(reference)
        let initialWeekStart = viewModel.calendarStartOfWeek
        
        viewModel.showPreviousWeek()
        
        XCTAssertTrue(Calendar.current.isDate(viewModel.selectedDate, inSameDayAs: reference))
        let expectedWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: initialWeekStart)!
        XCTAssertTrue(Calendar.current.isDate(viewModel.calendarStartOfWeek, inSameDayAs: expectedWeekStart))
    }
    
    @MainActor
    private func makeViewModel(tasks: [TaskItem] = []) -> TaskBoardViewModel {
        let authStore = AuthStore(
            authService: InMemoryAuthenticationService(),
            profileService: InMemoryUserProfileService()
        )
        let householdStore = HouseholdStore(service: InMemoryHouseholdService())
        let tagStore = TagStore(householdStore: householdStore, service: InMemoryTagService())
        let memberDirectory = MemberDirectory(profileService: InMemoryUserProfileService())
        let taskStore = TaskBoardStore(previewTasks: tasks)
        return TaskBoardViewModel(
            taskStore: taskStore,
            authStore: authStore,
            householdStore: householdStore,
            tagStore: tagStore,
            memberDirectory: memberDirectory
        )
    }
    
    private func referenceDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date!
    }
}
