//
//  TaskBoardService.swift
//  houseWork
//
//  Wraps Firestore task operations for better testability.
//

import Foundation
import FirebaseFirestore

protocol TaskBoardService {
    func observeTasks(householdId: String, handler: @escaping (Result<[TaskItem], Error>) -> Void) -> ListenerToken
    func createTask(_ task: TaskItem, householdId: String) async throws
    func updateTask(_ task: TaskItem, householdId: String) async throws
    func deleteTask(_ task: TaskItem, householdId: String) async throws
}

final class FirestoreTaskBoardService: TaskBoardService {
    private let db: Firestore
    
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }
    
    func observeTasks(householdId: String, handler: @escaping (Result<[TaskItem], Error>) -> Void) -> ListenerToken {
        let registration = taskCollection(for: householdId)
            .order(by: "dueDate", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error {
                    handler(.failure(error))
                    return
                }
                guard let documents = snapshot?.documents else {
                    handler(.success([]))
                    return
                }
                let tasks = documents.compactMap(TaskItem.init(document:))
                handler(.success(tasks))
            }
        return FirestoreListenerToken(registration: registration)
    }
    
    func createTask(_ task: TaskItem, householdId: String) async throws {
        try await taskCollection(for: householdId)
            .document(task.documentID)
            .setData(task.firestoreCreatePayload, merge: true)
    }
    
    func updateTask(_ task: TaskItem, householdId: String) async throws {
        try await taskCollection(for: householdId)
            .document(task.documentID)
            .setData(task.firestoreCreatePayload, merge: true)
    }
    
    func deleteTask(_ task: TaskItem, householdId: String) async throws {
        try await taskCollection(for: householdId)
            .document(task.documentID)
            .delete()
    }
    
    private func taskCollection(for householdId: String) -> CollectionReference {
        db.collection("households").document(householdId).collection("chores")
    }
}

final class InMemoryTaskBoardService: TaskBoardService {
    private var tasksByHousehold: [String: [TaskItem]] = [:]
    private var listeners: [String: [UUID: (Result<[TaskItem], Error>) -> Void]] = [:]
    
    func observeTasks(householdId: String, handler: @escaping (Result<[TaskItem], Error>) -> Void) -> ListenerToken {
        let id = UUID()
        var bucket = listeners[householdId, default: [:]]
        bucket[id] = handler
        listeners[householdId] = bucket
        handler(.success(tasksByHousehold[householdId] ?? []))
        return BlockListenerToken { [weak self] in
            self?.listeners[householdId]?.removeValue(forKey: id)
        }
    }
    
    func createTask(_ task: TaskItem, householdId: String) async throws {
        var tasks = tasksByHousehold[householdId, default: []]
        tasks.append(task)
        tasksByHousehold[householdId] = tasks
        notify(householdId: householdId)
    }
    
    func updateTask(_ task: TaskItem, householdId: String) async throws {
        guard var tasks = tasksByHousehold[householdId], let index = tasks.firstIndex(where: { $0.documentID == task.documentID }) else {
            return
        }
        tasks[index] = task
        tasksByHousehold[householdId] = tasks
        notify(householdId: householdId)
    }
    
    func deleteTask(_ task: TaskItem, householdId: String) async throws {
        guard var tasks = tasksByHousehold[householdId] else { return }
        tasks.removeAll { $0.documentID == task.documentID }
        tasksByHousehold[householdId] = tasks
        notify(householdId: householdId)
    }
    
    private func notify(householdId: String) {
        let tasks = tasksByHousehold[householdId] ?? []
        listeners[householdId]?.values.forEach { $0(.success(tasks)) }
    }
}
