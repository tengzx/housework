//
//  SettingsView.swift
//  houseWork
//
//  Manage account switches and shared resources such as tags.
//

import SwiftUI
import Combine

struct SettingsView: View {
    @EnvironmentObject private var authStore: AuthStore
    
    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let user = authStore.currentUser {
                        HStack {
                            AvatarCircle(member: user)
                            VStack(alignment: .leading) {
                                Text(user.name)
                                    .font(.headline)
                                Text("Active on this device")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Log out") { authStore.logout() }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        Text("Not signed in")
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("Firebase Email/Password 登录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("Household") {
                    NavigationLink {
                        TagManagementView()
                    } label: {
                        Label("Manage tags", systemImage: "tag")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct AvatarCircle: View {
    let member: HouseholdMember
    
    var body: some View {
        Text(member.initials)
            .font(.subheadline.bold())
            .foregroundColor(.white)
            .frame(width: 36, height: 36)
            .background(member.accentColor, in: Circle())
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthStore())
}
