//
//  TaskItem+Firestore.swift
//  houseWork
//
//  Mapping helpers for persisting tasks in Firestore.
//

import Foundation
import FirebaseFirestore

extension TaskItem {
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let title = data["title"] as? String else { return nil }
        guard let details = data["details"] as? String else { return nil }
        guard let statusRaw = data["status"] as? String,
              let status = TaskStatus(rawValue: statusRaw) else { return nil }
        guard let dueTimestamp = data["dueDate"] as? Timestamp else { return nil }
        guard let score = Self.intValue(from: data["score"]) else { return nil }
        let estimatedMinutes = Self.intValue(from: data["estimatedMinutes"]) ?? 30
        
        let roomTag = data["roomTag"] as? String ?? "General"
        let assignedArray = data["assignedMembers"] as? [[String: Any]] ?? []
        let assignedMembers = assignedArray.compactMap(HouseholdMember.init(firestoreData:))
        let originTemplateId = (data["originTemplateId"] as? String).flatMap(UUID.init(uuidString:))
        let completedAt = (data["completedAt"] as? Timestamp)?.dateValue()
        let documentID = document.documentID
        let id = UUID(uuidString: documentID) ?? UUID()
        
        self.init(
            id: id,
            title: title,
            documentID: documentID,
            details: details,
            status: status,
            dueDate: dueTimestamp.dateValue(),
            score: score,
            roomTag: roomTag,
            assignedMembers: assignedMembers,
            originTemplateID: originTemplateId,
            completedAt: completedAt,
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
        if completedAt == nil {
            payload["completedAt"] = FieldValue.delete()
        }
        return payload
    }
    
    func firestoreDiffPayload(comparedTo original: TaskItem) -> [String: Any] {
        var payload: [String: Any] = [:]
        
        if title != original.title {
            payload["title"] = title
        }
        if details != original.details {
            payload["details"] = details
        }
        if status != original.status {
            payload["status"] = status.rawValue
        }
        if dueDate != original.dueDate {
            payload["dueDate"] = Timestamp(date: dueDate)
        }
        if score != original.score {
            payload["score"] = score
        }
        if roomTag != original.roomTag {
            payload["roomTag"] = roomTag
        }
        if estimatedMinutes != original.estimatedMinutes {
            payload["estimatedMinutes"] = estimatedMinutes
        }
        if originTemplateID != original.originTemplateID {
            payload["originTemplateId"] = originTemplateID?.uuidString ?? FieldValue.delete()
        }
        if completionDateFieldNeedsUpdate(comparedTo: original) {
            if let completedAt {
                payload["completedAt"] = Timestamp(date: completedAt)
            } else {
                payload["completedAt"] = FieldValue.delete()
            }
        }
        if assignedMembers != original.assignedMembers {
            payload["assignedMembers"] = assignedMembers.map { $0.firestoreData }
        }
        
        if !payload.isEmpty {
            payload["updatedAt"] = FieldValue.serverTimestamp()
        }
        return payload
    }

    private func completionDateFieldNeedsUpdate(comparedTo original: TaskItem) -> Bool {
        switch (completedAt, original.completedAt) {
        case (nil, nil):
            return false
        case let (lhs?, rhs?):
            return lhs != rhs
        default:
            return true
        }
    }
    
    private var firestoreBody: [String: Any] {
        var payload: [String: Any] = [
            "title": title,
            "details": details,
            "status": status.rawValue,
            "dueDate": Timestamp(date: dueDate),
            "score": score,
            "roomTag": roomTag,
            "assignedMembers": assignedMembers.map { $0.firestoreData },
            "estimatedMinutes": estimatedMinutes
        ]
        if let originTemplateID {
            payload["originTemplateId"] = originTemplateID.uuidString
        }
        if let completedAt {
            payload["completedAt"] = Timestamp(date: completedAt)
        }
        return payload
    }
    
    private static func intValue(from value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let doubleValue = value as? Double { return Int(doubleValue) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}
