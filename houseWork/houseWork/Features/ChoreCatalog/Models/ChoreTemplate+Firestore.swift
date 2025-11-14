//
//  ChoreTemplate+Firestore.swift
//  houseWork
//
//  Maps chore templates to/from Firestore payloads.
//

import Foundation
import FirebaseFirestore

extension ChoreTemplate {
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let title = data["title"] as? String else { return nil }
        guard let baseScore = Self.intValue(from: data["baseScore"]) else { return nil }
        guard let estimatedMinutes = Self.intValue(from: data["estimatedMinutes"]) else { return nil }
        let rawFrequency = (data["frequency"] as? String) ?? ChoreFrequency.weekly.rawValue
        guard let frequency = ChoreFrequency(rawValue: rawFrequency) else { return nil }
        
        let details = data["details"] as? String ?? ""
        let tags = (data["tags"] as? [String])?.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ["General"]
        let identifier = UUID(uuidString: document.documentID) ?? UUID()
        
        self.init(
            id: identifier,
            title: title,
            details: details.isEmpty ? "No description yet." : details,
            tags: tags,
            frequency: frequency,
            baseScore: baseScore,
            estimatedMinutes: estimatedMinutes
        )
    }
    
    var firestoreCreatePayload: [String: Any] {
        var payload = firestoreBody
        payload["createdAt"] = FieldValue.serverTimestamp()
        payload["updatedAt"] = FieldValue.serverTimestamp()
        return payload
    }
    
    var firestoreUpdatePayload: [String: Any] {
        var payload = firestoreBody
        payload["updatedAt"] = FieldValue.serverTimestamp()
        return payload
    }
    
    private var firestoreBody: [String: Any] {
        [
            "title": title,
            "details": details,
            "tags": tags,
            "frequency": frequency.rawValue,
            "baseScore": baseScore,
            "estimatedMinutes": estimatedMinutes
        ]
    }
    
    private static func intValue(from value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let doubleValue = value as? Double { return Int(doubleValue) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}
