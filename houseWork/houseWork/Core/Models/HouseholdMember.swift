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
    var avatarURL: URL?
    
    init(id: UUID = UUID(), name: String, initials: String? = nil, accentColor: Color, avatarURL: URL? = nil) {
        self.id = id
        self.name = name
        self.initials = initials ?? HouseholdMember.initials(from: name)
        self.accentColor = accentColor
        self.avatarURL = avatarURL
    }
    
    static func initials(from name: String) -> String {
        let components = name
            .split(separator: " ")
            .compactMap { $0.first }
        return String(components.prefix(2))
    }
    
    func matches(_ other: HouseholdMember) -> Bool {
        if id == other.id { return true }
        let normalizedSelf = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedOther = other.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSelf.isEmpty, !normalizedOther.isEmpty else { return false }
        return normalizedSelf == normalizedOther
    }
    
    var avatarColor: Color {
        accentColor
    }
    
    static let defaultAvatarColors: [Color] = [
        Color(red: 0.96, green: 0.55, blue: 0.55),
        Color(red: 0.52, green: 0.67, blue: 0.99),
        Color(red: 0.55, green: 0.82, blue: 0.62),
        Color(red: 0.99, green: 0.76, blue: 0.42),
        Color(red: 0.71, green: 0.58, blue: 0.96),
        Color(red: 0.43, green: 0.78, blue: 0.84),
        Color(red: 0.97, green: 0.65, blue: 0.82),
        Color(red: 0.83, green: 0.66, blue: 0.46)
    ]
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
