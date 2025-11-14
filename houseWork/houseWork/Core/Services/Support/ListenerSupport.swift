//
//  ListenerSupport.swift
//  houseWork
//
//  Shared cancellable helpers for Firestore/Auth listeners.
//

import Foundation

protocol ListenerToken {
    func cancel()
}

final class BlockListenerToken: ListenerToken {
    private let onCancel: () -> Void
    private var isCancelled = false
    
    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }
    
    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel()
    }
    
    deinit {
        cancel()
    }
}
