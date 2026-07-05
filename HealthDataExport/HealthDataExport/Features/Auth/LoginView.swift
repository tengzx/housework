import SwiftUI

@MainActor
struct LoginView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var nickname = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage = ""
    @FocusState private var focusedField: Field?

    private enum Field { case nickname, password }

    private let accent = Color(hex: "FF7847")
    private let bg = Color(hex: "F5F6F8")

    private var canSubmit: Bool {
        !nickname.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty && !isSubmitting
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 26) {
                    header
                    fields
                    submitButton
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("老用户首次登录默认密码为 123456，登录成功后会保存 token。")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "8A8F9C"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.top, 80)
                .padding(.bottom, 32)
                .frame(maxWidth: 430)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIFE OS")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .tracking(4)
                .foregroundStyle(Color(hex: "1A1C20"))
            Text("登录以同步你的时间与健康数据")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "8A8F9C"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fields: some View {
        VStack(spacing: 14) {
            field(title: "昵称", text: $nickname, isSecure: false, field: .nickname)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focusedField = .password }

            field(title: "密码", text: $password, isSecure: true, field: .password)
                .submitLabel(.go)
                .onSubmit { if canSubmit { submit() } }
        }
    }

    @ViewBuilder
    private func field(title: String, text: Binding<String>, isSecure: Bool, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(hex: "9A9AA2"))
            Group {
                if isSecure {
                    SecureField("请输入\(title)", text: text)
                } else {
                    TextField("请输入\(title)", text: text)
                }
            }
            .font(.system(size: 16, weight: .medium))
            .focused($focusedField, equals: field)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(focusedField == field ? accent : Color(hex: "E4E6EB"), lineWidth: 1.5)
            )
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView().tint(.white)
                }
                Text(isSubmitting ? "登录中…" : "登录")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(canSubmit ? accent : accent.opacity(0.4), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .disabled(!canSubmit)
    }

    private func submit() {
        focusedField = nil
        errorMessage = ""
        isSubmitting = true
        Task {
            do {
                try await session.login(
                    nickname: nickname.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
