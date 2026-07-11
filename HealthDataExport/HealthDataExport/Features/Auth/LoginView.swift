import SwiftUI

@MainActor
struct LoginView: View {
    @EnvironmentObject private var localization: LocalizationStore
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
                    Text(localization.text("login.hint"))
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
            Text(localization.text("login.title"))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .tracking(4)
                .foregroundStyle(Color(hex: "1A1C20"))
            Text(localization.text("login.subtitle"))
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "8A8F9C"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fields: some View {
        VStack(spacing: 14) {
            field(titleKey: "login.nickname", text: $nickname, isSecure: false, field: .nickname)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focusedField = .password }

            field(titleKey: "login.password", text: $password, isSecure: true, field: .password)
                .submitLabel(.go)
                .onSubmit { if canSubmit { submit() } }
        }
    }

    @ViewBuilder
    private func field(titleKey: String, text: Binding<String>, isSecure: Bool, field: Field) -> some View {
        let title = localization.text(titleKey)
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(hex: "9A9AA2"))
            Group {
                if isSecure {
                    SecureField(localization.text("login.placeholder", title), text: text)
                } else {
                    TextField(localization.text("login.placeholder", title), text: text)
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
                Text(isSubmitting ? localization.text("login.submitting") : localization.text("login.submit"))
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
