import SwiftUI
import SwiftData
import AuthenticationServices

/// Sign in or create an account: Sign in with Apple or email and password.
struct AuthView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case create = "Create account"
        case signIn = "Sign in"
        var id: String { rawValue }
    }

    @State var mode: Mode
    var onSignedIn: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var context
    @State private var auth = AuthService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var message: String?
    @State private var isError = false
    @State private var nonce = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    VStack(alignment: .leading, spacing: KXSpacing.sm) {
                        KXLogo(size: 48)
                            .padding(.bottom, KXSpacing.xs)
                        KXAccentHeadline(plain: mode == .create ? "Back up your" : "Welcome", accented: mode == .create ? "training" : "back")
                        Text("An account backs up your plan, runs and lifts, and keeps them in sync across your devices. Everything still works offline.")
                            .font(KXFont.callout)
                            .foregroundStyle(KXColor.inkSecondary)
                    }
                    if auth.state == .unavailable {
                        Label("Accounts aren't set up in this version of the app yet. Your data is saved on this iPhone.", systemImage: "info.circle")
                            .font(KXFont.callout)
                            .kxCard(.tinted)
                    } else {
                        SignInWithAppleButton(mode == .create ? .signUp : .signIn) { request in
                            nonce = AuthService.makeNonce()
                            request.requestedScopes = [.email]
                            request.nonce = AuthService.sha256(nonce)
                        } onCompletion: { result in
                            handleApple(result)
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 50)
                        .clipShape(Capsule())

                        HStack {
                            Rectangle().fill(KXColor.border).frame(height: 1)
                            Text("or use email").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary).fixedSize()
                            Rectangle().fill(KXColor.border).frame(height: 1)
                        }

                        Picker("Mode", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        VStack(spacing: KXSpacing.md) {
                            TextField("Email", text: $email)
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(KXSpacing.md)
                                .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.sm))
                                .accessibilityIdentifier("auth.email")
                            SecureField(mode == .create ? "Password (at least 8 characters)" : "Password", text: $password)
                                .textContentType(mode == .create ? .newPassword : .password)
                                .padding(KXSpacing.md)
                                .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.sm))
                                .accessibilityIdentifier("auth.password")
                        }

                        if let message {
                            Label(message, systemImage: isError ? "exclamationmark.circle" : "envelope")
                                .font(KXFont.callout)
                                .foregroundStyle(KXColor.ink)
                                .kxCard(isError ? .accent : .tinted)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            if working { ProgressView().tint(KXColor.onAccent) } else { Text(mode.rawValue) }
                        }
                        .buttonStyle(.kx(.primary, fullWidth: true))
                        .disabled(!canSubmit || working)
                        .opacity(canSubmit ? 1 : 0.5)

                        if mode == .signIn {
                            Button("Forgot password?") { Task { await resetPassword() } }
                                .font(KXFont.callout)
                                .foregroundStyle(KXColor.accent)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
    }

    private var canSubmit: Bool {
        email.contains("@") && email.contains(".") && password.count >= (mode == .create ? 8 : 1)
    }

    private func submit() async {
        working = true
        defer { working = false }
        do {
            switch mode {
            case .signIn:
                try await auth.signIn(email: email, password: password)
                await finish()
            case .create:
                if try await auth.signUp(email: email, password: password) {
                    await finish()
                } else {
                    isError = false
                    message = "Check your inbox: tap the link we sent to \(email), then come back and sign in."
                    mode = .signIn
                }
            }
        } catch {
            isError = true
            message = error.localizedDescription
        }
    }

    private func resetPassword() async {
        guard email.contains("@") else {
            isError = true
            message = "Enter your email above first."
            return
        }
        do {
            try await auth.sendPasswordReset(email: email)
            isError = false
            message = "If there's an account for \(email), a reset link is on its way."
        } catch {
            isError = true
            message = error.localizedDescription
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8) else {
                isError = true
                message = "Apple didn't return a sign-in token. Please try again."
                return
            }
            Task {
                working = true
                defer { working = false }
                do {
                    try await auth.signInWithApple(idToken: token, nonce: nonce)
                    await finish()
                } catch {
                    isError = true
                    message = error.localizedDescription
                }
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            isError = true
            message = error.localizedDescription
        }
    }

    private func finish() async {
        await SyncService.shared.sync(context: context)
        onSignedIn()
        dismiss()
    }
}
