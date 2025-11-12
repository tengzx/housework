//
//  LoginView.swift
//  houseWork
//
//  Email / password login powered by Firebase Auth.
//

import SwiftUI

struct LoginView: View {
    enum Mode {
        case signIn
        case signUp
    }
    
    @EnvironmentObject private var authStore: AuthStore
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var fullName: String = ""
    @State private var mode: Mode = .signIn
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("houseWork")
                    .font(.largeTitle.bold())
                Text(mode == .signIn ? "Sign in to sync chores" : "Create your account")
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 16) {
                if mode == .signUp {
                    TextField("Full Name", text: $fullName)
                        .textFieldStyle(.roundedBorder)
                }
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
            
            VStack(spacing: 12) {
                Button {
                    Task { await handlePrimaryAction() }
                } label: {
                    if authStore.isProcessing {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text(mode == .signIn ? "Sign In" : "Sign Up")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!formIsValid || authStore.isProcessing)
                
                Button {
                    mode = (mode == .signIn) ? .signUp : .signIn
                    authStore.authError = nil
                } label: {
                    Text(mode == .signIn ? "Need an account? Sign up" : "Already have an account? Sign in")
                        .font(.footnote)
                }
            }
            .padding(.horizontal)
            
            if let error = authStore.authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
    
    private var formIsValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        (mode == .signIn || !fullName.trimmingCharacters(in: .whitespaces).isEmpty)
    }
    
    private func handlePrimaryAction() async {
        switch mode {
        case .signIn:
            await authStore.signIn(email: email, password: password)
        case .signUp:
            await authStore.signUp(name: fullName, email: email, password: password)
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthStore())
}
