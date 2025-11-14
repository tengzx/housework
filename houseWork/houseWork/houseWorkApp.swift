//
//  houseWorkApp.swift
//  houseWork
//
//  Created by tengzx on 12.11.2025.
//

import SwiftUI
import FirebaseCore

@main
struct houseWorkApp: App {
    init() {
        FirebaseApp.configure()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
