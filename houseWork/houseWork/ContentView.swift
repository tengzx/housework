//
//  ContentView.swift
//  houseWork
//
//  Created by tengzx on 12.11.2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var taskBoardStore = TaskBoardStore()
    
    var body: some View {
        TabView {
            TaskBoardView()
                .tabItem {
                    Label("Board", systemImage: "rectangle.grid.2x2")
                }
            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.line.uptrend.xyaxis")
                }
            ChoreCatalogView()
                .tabItem {
                    Label("Catalog", systemImage: "list.bullet.rectangle")
                }
        }
        .environmentObject(taskBoardStore)
    }
}

#Preview {
    ContentView()
}
