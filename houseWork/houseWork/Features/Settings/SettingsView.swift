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
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var householdNameDraft: String = ""
    @State private var householdIdDraft: String = ""
    
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
                    
                    Text("Firebase Email/Password sign-in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("Household") {
                    HouseholdSection()
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct HouseholdSection: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    
    var body: some View {
        if householdStore.households.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("No household found")
                    .font(.headline)
                Text("Create or join a household to start managing chores.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    HouseholdManagementView()
                } label: {
                    Label("Create Household", systemImage: "house.badge.plus")
                        .font(.subheadline.bold())
                }
            }
            .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current: \(householdStore.householdName)")
                Text("ID: \(householdStore.householdId)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            NavigationLink {
                HouseholdManagementView()
            } label: {
                Label("Manage households", systemImage: "house")
            }
            NavigationLink {
                TagManagementView()
            } label: {
                Label("Manage tags", systemImage: "tag")
            }
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
