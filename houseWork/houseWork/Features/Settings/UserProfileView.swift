//
//  UserProfileView.swift
//  houseWork
//
//  Form for editing the signed-in user's display name and avatar color.
//

import SwiftUI

struct UserProfileView: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section(LocalizedStringKey("userProfile.section.info")) {
                TextField(LocalizedStringKey("userProfile.field.name"), text: $viewModel.name)
                HStack {
                    Text(LocalizedStringKey("userProfile.field.email"))
                    Spacer()
                    Text(viewModel.email)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            
            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            Section {
                Button(role: .destructive) {
                    Haptics.impact()
                    viewModel.logout()
                    dismiss()
                } label: {
                    Text(LocalizedStringKey("settings.account.logout"))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(LocalizedStringKey("userProfile.title"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(LocalizedStringKey("userProfile.button.save")) {
                    Task {
                        if await viewModel.save() {
                            dismiss()
                        }
                    }
                }
                .disabled(!viewModel.canSave)
            }
        }
    }
}

#Preview {
    let authStore = AuthStore(
        authService: InMemoryAuthenticationService(
            initialSession: AuthSession(userId: "user-1", displayName: "Preview User", email: "preview@sample.com")
        ),
        profileService: InMemoryUserProfileService(
            seedProfiles: [
                "user-1": UserProfile(id: "user-1", name: "Preview User", email: "preview@sample.com", accentColor: .pink, memberId: UUID().uuidString)
            ]
        )
    )
    return navigationContainer {
        UserProfileView(viewModel: UserProfileViewModel(authStore: authStore))
    }
}
