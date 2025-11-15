//
//  LoginView.swift
//  houseWork
//
//  Email / password login powered by Firebase Auth.
//

import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: LoginViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(LocalizedStringKey("login.title"))
                    .font(.largeTitle.bold())
                Text(viewModel.mode == .signIn ? LocalizedStringKey("login.subtitle.signIn") : LocalizedStringKey("login.subtitle.signUp"))
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 16) {
                if viewModel.mode == .signUp {
                    TextField(LocalizedStringKey("login.field.fullName"), text: $viewModel.fullName)
                        .textFieldStyle(.roundedBorder)
                }
                TextField(LocalizedStringKey("login.field.email"), text: $viewModel.email)
#if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
#endif
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                SecureField(LocalizedStringKey("login.field.password"), text: $viewModel.password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
            
            VStack(spacing: 12) {
                Button {
                    Haptics.impact()
                    Task { await viewModel.performPrimaryAction() }
                } label: {
                    if viewModel.isProcessing {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text(viewModel.mode == .signIn ? LocalizedStringKey("login.button.primary.signIn") : LocalizedStringKey("login.button.primary.signUp"))
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isFormValid || viewModel.isProcessing)
                
                Button {
                    Haptics.impact()
                    viewModel.toggleMode()
                } label: {
                    Text(viewModel.mode == .signIn ? LocalizedStringKey("login.button.toggle.toSignUp") : LocalizedStringKey("login.button.toggle.toSignIn"))
                        .font(.footnote)
                }

#if canImport(UIKit)
                Button {
                    Haptics.impact()
                    Task { await viewModel.signInWithGoogle() }
                } label: {
                    Label(LocalizedStringKey("login.button.google"), systemImage: "g.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isProcessing)
#endif
            }
            .padding(.horizontal)
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
    
}

#Preview {
    LoginView(viewModel: LoginViewModel(authStore: AuthStore()))
}
