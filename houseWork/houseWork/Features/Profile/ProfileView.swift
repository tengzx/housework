//
//  ProfileView.swift
//  houseWork
//
//  Lightweight authentication screen for selecting the active household member.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authStore: AuthStore
    
    var body: some View {
        NavigationStack {
            List {
                Section("Current User") {
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
                            Button("Log out") {
                                authStore.logout()
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Text("Not signed in")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Switch User") {
                    ForEach(authStore.availableMembers) { member in
                        Button {
                            authStore.login(as: member)
                        } label: {
                            HStack {
                                AvatarCircle(member: member)
                                VStack(alignment: .leading) {
                                    Text(member.name)
                                    Text("Tap to sign in")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if authStore.currentUser?.id == member.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Profile")
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
    ProfileView()
        .environmentObject(AuthStore())
}
