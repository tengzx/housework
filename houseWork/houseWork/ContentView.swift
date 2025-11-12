//
//  ContentView.swift
//  houseWork
//
//  Created by tengzx on 12.11.2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TaskBoardView()
                .tabItem {
                    Label("Board", systemImage: "rectangle.grid.2x2")
                }
            ChoreCatalogView()
                .tabItem {
                    Label("Catalog", systemImage: "list.bullet.rectangle")
                }
        }
    }
}

#Preview {
    ContentView()
}
