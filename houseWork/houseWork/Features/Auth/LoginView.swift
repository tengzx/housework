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
                Text("houseWork")
                    .font(.largeTitle.bold())
                Text(viewModel.mode == .signIn ? "Sign in to sync chores" : "Create your account")
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 16) {
                if viewModel.mode == .signUp {
                    TextField("Full Name", text: $viewModel.fullName)
                        .textFieldStyle(.roundedBorder)
                }
                TextField("Email", text: $viewModel.email)
#if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
#endif
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $viewModel.password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
            
            VStack(spacing: 12) {
                Button {
                    Task { await viewModel.performPrimaryAction() }
                } label: {
                    if viewModel.isProcessing {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text(viewModel.mode == .signIn ? "Sign In" : "Sign Up")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isFormValid || viewModel.isProcessing)
                
                Button {
                    viewModel.toggleMode()
                } label: {
                    Text(viewModel.mode == .signIn ? "Need an account? Sign up" : "Already have an account? Sign in")
                        .font(.footnote)
                }
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
