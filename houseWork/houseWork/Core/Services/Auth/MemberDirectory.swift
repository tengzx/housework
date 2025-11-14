//
//  MemberDirectory.swift
//  houseWork
//
//  Observes user profiles and exposes hydrated household members keyed by memberId.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class MemberDirectory: ObservableObject {
    @Published private(set) var membersById: [UUID: HouseholdMember] = [:]
    @Published var errorMessage: String?
    
    private let profileService: UserProfileService
    private var listener: ListenerToken?
    
    init(profileService: UserProfileService = FirestoreUserProfileService()) {
        self.profileService = profileService
        listener = profileService.observeProfiles { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let profiles):
                    self?.errorMessage = nil
                    self?.membersById = profiles.reduce(into: [:]) { dict, profile in
                        guard let uuid = profile.memberUUID else { return }
                        dict[uuid] = profile.asHouseholdMember(fallbackId: uuid)
                    }
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    deinit {
        listener?.cancel()
    }
    
    func replaceMembers(in tasks: [TaskItem]) -> [TaskItem] {
        tasks.map { task in
            var updated = task
            updated.assignedMembers = task.assignedMembers.map { member in
                membersById[member.id] ?? member
            }
            return updated
        }
    }
    
    func member(for id: UUID) -> HouseholdMember? {
        membersById[id]
    }
}
