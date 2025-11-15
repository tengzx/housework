//
//  houseWorkApp.swift
//  houseWork
//
//  Created by tengzx on 12.11.2025.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct houseWorkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        FirebaseApp.configure()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    _ = Auth.auth().canHandle(url)
                }
        }
    }
}
