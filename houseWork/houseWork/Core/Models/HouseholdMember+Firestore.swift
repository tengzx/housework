//
//  HouseholdMember+Firestore.swift
//  houseWork
//
//  Serialization helpers used when persisting members on chores/tasks.
//

import Foundation
import SwiftUI

extension HouseholdMember {
    init?(firestoreData: [String: Any]) {
        guard let name = firestoreData["name"] as? String else { return nil }
        let idString = firestoreData["id"] as? String
        let uuid = idString.flatMap(UUID.init(uuidString:)) ?? UUID()
        let initials = firestoreData["initials"] as? String ?? HouseholdMember.initials(from: name)
        let colorHex = firestoreData["color"] as? String
        let color = colorHex.flatMap(Color.init(hex:)) ?? .blue
        self.init(id: uuid, name: name, initials: initials, accentColor: color)
    }
    
    var firestoreData: [String: Any] {
        [
            "id": id.uuidString,
            "name": name,
            "initials": initials,
            "color": accentColor.hexString ?? "#2563EBFF"
        ]
    }
}
