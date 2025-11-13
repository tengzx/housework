//
//  HouseholdMember.swift
//  houseWork
//
//  Shared member model reused across multiple features.
//

import SwiftUI

struct HouseholdMember: Identifiable, Hashable {
    let id: UUID
    var name: String
    var initials: String
    var accentColor: Color
    
    init(id: UUID = UUID(), name: String, initials: String? = nil, accentColor: Color) {
        self.id = id
        self.name = name
        self.initials = initials ?? HouseholdMember.initials(from: name)
        self.accentColor = accentColor
    }
    
    static func initials(from name: String) -> String {
        let components = name
            .split(separator: " ")
            .compactMap { $0.first }
        return String(components.prefix(2))
    }
}

extension HouseholdMember {
    static let samples: [HouseholdMember] = [
        HouseholdMember(name: "Alex Chen", accentColor: .pink),
        HouseholdMember(name: "Jamie Patel", accentColor: .blue),
        HouseholdMember(name: "Morgan Lee", accentColor: .green),
        HouseholdMember(name: "Taylor Kim", accentColor: .purple),
        HouseholdMember(name: "Riley Smith", accentColor: .orange)
    ]
}
