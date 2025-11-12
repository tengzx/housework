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
                Text(mode == .signIn ? "登录以同步家务数据" : "创建家务账户")
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 16) {
                if mode == .signUp {
                    TextField("姓名", text: $fullName)
                        .textFieldStyle(.roundedBorder)
                }
                TextField("邮箱", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                SecureField("密码", text: $password)
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
                        Text(mode == .signIn ? "登录" : "注册")
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
                    Text(mode == .signIn ? "没有账号？点击注册" : "已有账号？点击登录")
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
