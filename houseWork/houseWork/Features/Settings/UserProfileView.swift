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
            
            Section(LocalizedStringKey("userProfile.section.avatar")) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(Array(viewModel.colorOptions.enumerated()), id: \.offset) { entry in
                        let color = entry.element
                        let isSelected = color.hexString == viewModel.selectedColor.hexString
                        Button {
                            viewModel.selectedColor = color
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.white)
                                    }
                                }
                                .overlay(
                                    Circle().stroke(Color.primary.opacity(isSelected ? 0.6 : 0.1), lineWidth: isSelected ? 2 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LocalizedStringKey("userProfile.avatarColorOption"))
                    }
                }
                .padding(.vertical, 4)
            }
            
            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
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
