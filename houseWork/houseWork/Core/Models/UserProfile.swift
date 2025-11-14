//
//  UserProfile.swift
//  houseWork
//
//  Represents the authenticated user's persisted settings.
//

import SwiftUI

struct UserProfile: Equatable {
    let id: String
    var name: String
    var email: String
    var accentColor: Color
    var memberId: String
    
    init(id: String, name: String, email: String, accentColor: Color, memberId: String) {
        self.id = id
        self.name = name
        self.email = email
        self.accentColor = accentColor
        self.memberId = memberId
    }
}

extension UserProfile {
    init?(id: String, data: [String: Any]) {
        guard let name = data["displayName"] as? String ?? data["name"] as? String else { return nil }
        let email = data["email"] as? String ?? ""
        let colorHex = data["avatarColor"] as? String ?? data["accentColor"] as? String ?? data["color"] as? String
        let color = colorHex.flatMap(Color.init(hex:)) ?? .blue
        let memberId = data["memberId"] as? String ?? UUID().uuidString
        self.init(id: id, name: name, email: email, accentColor: color, memberId: memberId)
    }
    
    var firestoreData: [String: Any] {
        var payload: [String: Any] = [
            "displayName": name,
            "name": name,
            "email": email,
            "memberId": memberId
        ]
        if let hex = accentColor.hexString {
            payload["avatarColor"] = hex
            payload["accentColor"] = hex
        }
        return payload
    }
    
    var memberUUID: UUID? {
        UUID(uuidString: memberId)
    }
    
    func asHouseholdMember(fallbackId: UUID) -> HouseholdMember {
        let identifier = memberUUID ?? fallbackId
        return HouseholdMember(id: identifier, name: name, initials: HouseholdMember.initials(from: name), accentColor: accentColor)
    }
}
