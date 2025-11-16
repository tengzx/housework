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
    var avatarURL: URL?
    var points: Int
    var lifetimePoints: Int
    
    init(
        id: String,
        name: String,
        email: String,
        accentColor: Color,
        memberId: String,
        avatarURL: URL? = nil,
        points: Int = 0,
        lifetimePoints: Int = 0
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.accentColor = accentColor
        self.memberId = memberId
        self.avatarURL = avatarURL
        self.points = points
        self.lifetimePoints = lifetimePoints
    }
}

extension UserProfile {
    init?(id: String, data: [String: Any]) {
        guard let name = data["displayName"] as? String ?? data["name"] as? String else { return nil }
        let email = data["email"] as? String ?? ""
        let colorHex = data["avatarColor"] as? String ?? data["accentColor"] as? String ?? data["color"] as? String
        let color = colorHex.flatMap(Color.init(hex:)) ?? .blue
        let memberId = data["memberId"] as? String ?? UUID().uuidString
        let avatarURLString = data["avatarURL"] as? String
        let avatarURL = avatarURLString.flatMap { URL(string: $0) }
        let points = data["points"] as? Int ?? 0
        let lifetime = data["lifetimePoints"] as? Int ?? points
        self.init(id: id, name: name, email: email, accentColor: color, memberId: memberId, avatarURL: avatarURL, points: points, lifetimePoints: lifetime)
    }
    
    var firestoreData: [String: Any] {
        var payload: [String: Any] = [
            "displayName": name,
            "name": name,
            "email": email,
            "memberId": memberId,
            "points": points,
            "lifetimePoints": lifetimePoints
        ]
        if let hex = accentColor.hexString {
            payload["avatarColor"] = hex
            payload["accentColor"] = hex
        }
        if let avatarURL {
            payload["avatarURL"] = avatarURL.absoluteString
        }
        return payload
    }
    
    var memberUUID: UUID? {
        UUID(uuidString: memberId)
    }
    
    func asHouseholdMember(fallbackId: UUID) -> HouseholdMember {
        let identifier = memberUUID ?? fallbackId
        return HouseholdMember(id: identifier, name: name, initials: HouseholdMember.initials(from: name), accentColor: accentColor, avatarURL: avatarURL)
    }
}
