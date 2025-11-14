//
//  TaskBoardStore.swift
//  houseWork
//
//  Shared store that syncs the household task board with Firestore.
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore

@MainActor
final class TaskBoardStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem]
    @Published private(set) var isLoading: Bool
    @Published var error: String?
    @Published var mutationError: String?
    @Published private(set) var isMutating = false
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var householdCancellable: AnyCancellable?
    private weak var householdStore: HouseholdStore?
    private var currentHouseholdId: String = ""
    private let isPreviewMode: Bool
    
    init(householdStore: HouseholdStore) {
        self.householdStore = householdStore
        self.tasks = []
        self.isLoading = true
        self.isPreviewMode = false
        self.currentHouseholdId = ""
        householdCancellable = householdStore.$householdId
            .removeDuplicates()
            .sink { [weak self] newId in
                guard let self else { return }
                Task { @MainActor in
                    await self.switchHousehold(to: newId)
                }
            }
    }
    
    init(previewTasks: [TaskItem] = TaskItem.fixtures()) {
        self.tasks = previewTasks
        self.isLoading = false
        self.isPreviewMode = true
        self.householdStore = nil
    }
    
    deinit {
        listener?.remove()
        householdCancellable?.cancel()
    }
    
    // MARK: - Firestore sync
    
    private func switchHousehold(to id: String) async {
        guard !isPreviewMode else { return }
        
        if id.isEmpty || id == "demo-household" {
            listener?.remove()
            listener = nil
            currentHouseholdId = ""
            tasks = []
            isLoading = false
            error = nil
            return
        }
        
        guard id != currentHouseholdId else { return }
        listener?.remove()
        currentHouseholdId = id
        tasks = []
        isLoading = true
        attachListener(to: id)
    }
    
    private func attachListener(to householdId: String) {
        guard !isPreviewMode, !householdId.isEmpty else { return }
        listener = taskCollection(for: householdId)
            .order(by: "dueDate", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor in
                    if let error {
                        self.error = error.localizedDescription
                        self.isLoading = false
                        return
                    }
                    guard let documents = snapshot?.documents else { return }
                    self.tasks = documents.compactMap(TaskItem.init(document:))
                    self.isLoading = false
                }
            }
    }
    
    // MARK: - Mutations
    
    @discardableResult
    func enqueue(template: ChoreTemplate, assignedTo member: HouseholdMember?) async -> Bool {
        let task = TaskItem(
            title: template.title,
            details: template.details,
            status: .backlog,
            dueDate: Date().addingTimeInterval(60 * 60 * 24),
            score: template.baseScore,
            roomTag: template.tags.first ?? "General",
            assignedMembers: member.map { [$0] } ?? [],
            originTemplateID: template.id,
            estimatedMinutes: template.estimatedMinutes
        )
        return await createTask(task)
    }
    
    @discardableResult
    func startTask(_ task: TaskItem, assignedTo member: HouseholdMember?) async -> Bool {
        guard canMutate(task: task, actingUser: member) else {
            mutationError = "You can only start tasks assigned to you."
            return false
        }
        return await updateTask(task) { item in
            var updated = item
            updated.status = .inProgress
            if updated.assignedMembers.isEmpty, let member {
                updated.assignedMembers = [member]
            }
            updated.completedAt = nil
            return updated
        }
    }
    
    @discardableResult
    func createTask(
        title: String,
        details: String,
        dueDate: Date,
        score: Int,
        roomTag: String,
        assignedMembers: [HouseholdMember],
        estimatedMinutes: Int
    ) async -> Bool {
        let newTask = TaskItem(
            title: title,
            details: details,
            status: .backlog,
            dueDate: dueDate,
            score: score,
            roomTag: roomTag,
            assignedMembers: assignedMembers,
            estimatedMinutes: estimatedMinutes
        )
        return await createTask(newTask)
    }
    
    @discardableResult
    func completeTask(_ task: TaskItem, actingUser: HouseholdMember?) async -> Bool {
        guard canMutate(task: task, actingUser: actingUser) else {
            mutationError = "You can only update tasks assigned to you."
            return false
        }
        return await updateTask(task) { item in
            var updated = item
            updated.status = .completed
            updated.completedAt = Date()
            return updated
        }
    }
    
    func refresh() async {
        guard !isPreviewMode else { return }
        guard !currentHouseholdId.isEmpty else { return }
        listener?.remove()
        listener = nil
        isLoading = true
        tasks = []
        attachListener(to: currentHouseholdId)
    }
    
    @discardableResult
    func deleteTask(_ task: TaskItem) async -> Bool {
        if isPreviewMode {
            removeLocalTask(task)
            return true
        }
        
        return await performMutation {
            let householdId = try requireHouseholdId()
            try await taskCollection(for: householdId)
                .document(task.documentID)
                .delete()
        }
    }
    
    @discardableResult
    func updateTaskDetails(
        _ task: TaskItem,
        title: String,
        details: String,
        dueDate: Date,
        score: Int,
        roomTag: String,
        estimatedMinutes: Int
    ) async -> Bool {
        return await updateTask(task) { item in
            var updated = item
            updated.title = title
            updated.details = details
            updated.dueDate = dueDate
            updated.score = score
            updated.roomTag = roomTag
            updated.estimatedMinutes = estimatedMinutes
            return updated
        }
    }
    
    
    private func createTask(_ task: TaskItem) async -> Bool {
        if isPreviewMode {
            withAnimation {
                tasks.insert(task, at: 0)
            }
            return true
        }
        
        return await performMutation {
            let householdId = try requireHouseholdId()
            try await taskCollection(for: householdId)
                .document(task.documentID)
                .setData(task.firestoreCreatePayload)
        }
    }
    
    private func updateTask(_ task: TaskItem, transform: (TaskItem) -> TaskItem) async -> Bool {
        let updatedTask = transform(task)
        if isPreviewMode {
            applyLocalUpdate(updatedTask)
            return true
        }
        
        let payload = updatedTask.firestoreDiffPayload(comparedTo: task)
        guard !payload.isEmpty else { return true }
        
        let success = await performMutation {
            let householdId = try requireHouseholdId()
            try await taskCollection(for: householdId)
                .document(task.documentID)
                .updateData(payload)
        }
        if success {
            await MainActor.run {
                self.applyLocalUpdate(updatedTask)
            }
        }
        return success
    }
    
    private func applyLocalUpdate(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        withAnimation {
            tasks[index] = task
        }
    }
    
    private func removeLocalTask(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        withAnimation {
            tasks.remove(at: index)
        }
    }
    
    private func performMutation(_ work: () async throws -> Void) async -> Bool {
        isMutating = true
        defer { isMutating = false }
        do {
            try await work()
            mutationError = nil
            return true
        } catch {
            mutationError = error.localizedDescription
            return false
        }
    }
    
    private func requireHouseholdId() throws -> String {
        guard !currentHouseholdId.isEmpty else {
            throw TaskBoardError.missingHousehold
        }
        return currentHouseholdId
    }
    
    private func taskCollection(for householdId: String) -> CollectionReference {
        db.collection("households")
            .document(householdId)
            .collection("chores")
    }
    
    private func canMutate(task: TaskItem, actingUser: HouseholdMember?) -> Bool {
        guard let user = actingUser else { return false }
        return task.assignedMembers.contains(where: { $0.matches(user) })
    }
    
    // MARK: - Metrics
    
    var completionRate: Double {
        let total = Double(tasks.count)
        guard total > 0 else { return 0 }
        let done = Double(tasks.filter { $0.status == .completed }.count)
        return done / total
    }
    
    var overdueCount: Int {
        tasks.filter { $0.status != .completed && $0.dueDate < Date() }.count
    }
}

extension TaskBoardStore {
    enum TaskBoardError: LocalizedError {
        case missingHousehold
        
        var errorDescription: String? {
            switch self {
            case .missingHousehold:
                return "Missing household context. Select a household and try again."
            }
        }
    }
}
