//
//  AuthStore.swift
//  houseWork
//
//  Simple in-memory authentication store for selecting the active household member.
//

import Foundation
import SwiftUI
import Combine

final class AuthStore: ObservableObject {
    @Published var currentUser: HouseholdMember?
    let availableMembers: [HouseholdMember]
    
    init(members: [HouseholdMember] = HouseholdMember.samples) {
        self.availableMembers = members
        self.currentUser = members.first
    }
    
    func login(as member: HouseholdMember) {
        currentUser = member
    }
    
    func logout() {
        currentUser = nil
    }
}
