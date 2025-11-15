//
//  ContentViewModel.swift
//  houseWork
//
//  Root view model that wires shared stores and drives high-level navigation.
//

import Foundation
import Combine

@MainActor
final class ContentViewModel: ObservableObject {
    enum PresentationState {
        case loadingAccount
        case authentication
        case loadingHousehold
        case needsHousehold
        case dashboard
    }
    
    @Published private(set) var presentationState: PresentationState = .loadingAccount
    
    let authStore: AuthStore
    let householdStore: HouseholdStore
    let taskBoardStore: TaskBoardStore
    let tagStore: TagStore
    let memberDirectory: MemberDirectory
    let rewardsStore: RewardsStore
    let taskBoardViewModel: TaskBoardViewModel
    let rewardsViewModel: RewardsViewModel
    let loginViewModel: LoginViewModel
    
    private var cancellables: Set<AnyCancellable> = []
    
    init(
        authStore: AuthStore,
        householdStore: HouseholdStore
    ) {
        self.authStore = authStore
        self.householdStore = householdStore
        self.taskBoardStore = TaskBoardStore(householdStore: householdStore)
        self.tagStore = TagStore(householdStore: householdStore)
        self.memberDirectory = MemberDirectory()
        self.rewardsStore = RewardsStore(householdStore: householdStore)
        self.taskBoardViewModel = TaskBoardViewModel(
            taskStore: taskBoardStore,
            authStore: authStore,
            householdStore: householdStore,
            tagStore: tagStore,
            memberDirectory: memberDirectory
        )
        self.rewardsViewModel = RewardsViewModel(
            rewardsStore: rewardsStore,
            taskStore: taskBoardStore,
            authStore: authStore
        )
        self.loginViewModel = LoginViewModel(authStore: authStore)
        bindStores()
    }
    
    func onAppear() {
        householdStore.updateUserContext(userId: authStore.firebaseUserId, force: true)
        refreshPresentationState()
    }
    
    private func bindStores() {
        authStore.$firebaseUserId
            .removeDuplicates()
            .sink { [weak self] userId in
                guard let self else { return }
                Task { @MainActor in
                    self.householdStore.updateUserContext(userId: userId, force: true)
                }
            }
            .store(in: &cancellables)
        
        let signals: [AnyPublisher<Void, Never>] = [
            authStore.$isLoading.eraseToVoid(),
            authStore.$didProcessInitialSession.eraseToVoid(),
            authStore.$currentUser.eraseToVoid(),
            householdStore.$isLoading.eraseToVoid(),
            householdStore.$households.eraseToVoid()
        ]
        
        Publishers.MergeMany(signals)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.refreshPresentationState()
            }
            .store(in: &cancellables)
    }
    
    private func refreshPresentationState() {
        if authStore.isLoading || !authStore.didProcessInitialSession {
            presentationState = .loadingAccount
        } else if authStore.currentUser == nil {
            presentationState = .authentication
        } else if householdStore.isLoading {
            presentationState = .loadingHousehold
        } else if householdStore.households.isEmpty {
            presentationState = .needsHousehold
        } else {
            presentationState = .dashboard
        }
    }
}

private extension Publisher where Failure == Never {
    func eraseToVoid() -> AnyPublisher<Void, Never> {
        map { _ in () }.eraseToAnyPublisher()
    }
}
