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
    @EnvironmentObject private var tagStore: TagStore
    @EnvironmentObject private var languageStore: LanguageStore
    @State private var householdNameDraft: String = ""
    @State private var householdIdDraft: String = ""
    
    var body: some View {
        navigationContainer {
            List {
                Section(LocalizedStringKey("settings.section.account")) {
                    if let user = authStore.currentUser {
                        NavigationLink {
                            UserProfileView(viewModel: UserProfileViewModel(authStore: authStore))
                        } label: {
                            HStack(spacing: 12) {
                                AvatarCircle(member: user)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(user.name)
                                        .font(.headline)
                                    Text(accountEmailText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(LocalizedStringKey("settings.account.tapToEdit"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button(LocalizedStringKey("settings.account.logout")) { authStore.logout() }
                            .buttonStyle(.bordered)
                    } else {
                        Text(LocalizedStringKey("settings.account.notSignedIn"))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(LocalizedStringKey("settings.account.authDescription"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section(LocalizedStringKey("settings.section.household")) {
                    HouseholdSection()
                }
                
                Section(LocalizedStringKey("settings.language.section")) {
                    Picker(
                        LocalizedStringKey("settings.language.picker"),
                        selection: Binding(
                            get: { languageStore.selectedLanguage },
                            set: { languageStore.select($0) }
                        )
                    ) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayKey).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
    
    private var accountEmailText: String {
        authStore.userProfile?.email ?? authStore.currentEmail ?? String(localized: "settings.account.email.placeholder")
    }
}

private struct HouseholdSection: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var tagStore: TagStore
    
    var body: some View {
        if householdStore.households.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedStringKey("settings.household.none"))
                    .font(.headline)
                Text(LocalizedStringKey("settings.household.instructions"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    HouseholdManagementView()
                } label: {
                    Label(LocalizedStringKey("settings.household.create"), systemImage: "house.badge.plus")
                        .font(.subheadline.bold())
                }
            }
            .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: String(localized: "settings.household.currentPrefix"), householdStore.householdName))
                Text("household.id.format \(householdStore.householdId)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            NavigationLink {
                HouseholdManagementView()
            } label: {
                Label(LocalizedStringKey("settings.household.manageHouseholds"), systemImage: "house")
            }
            NavigationLink {
                TagManagementView()
                    .environmentObject(tagStore)
            } label: {
                Label(LocalizedStringKey("settings.household.manageTags"), systemImage: "tag")
            }
        }
    }
}

private struct AvatarCircle: View {
    let member: HouseholdMember
    
    var body: some View {
        MemberAvatarView(member: member, size: 36)
    }
}

#Preview {
    let householdStore = HouseholdStore()
    let tagStore = TagStore(householdStore: householdStore)
    let languageStore = LanguageStore()
    let session = AuthSession(userId: "preview-user", displayName: "Casey Lee", email: "casey@example.com")
    let authStore = AuthStore(
        authService: InMemoryAuthenticationService(initialSession: session),
        profileService: InMemoryUserProfileService(
            seedProfiles: [
                session.userId: UserProfile(id: session.userId, name: "Casey Lee", email: "casey@example.com", accentColor: .purple, memberId: UUID().uuidString)
            ]
        )
    )
    return navigationContainer {
        SettingsView()
            .environmentObject(authStore)
            .environmentObject(householdStore)
            .environmentObject(tagStore)
            .environmentObject(languageStore)
    }
}
