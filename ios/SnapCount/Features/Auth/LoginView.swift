import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    form
                    status
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
                .padding(.top, 42)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(JieziTheme.mint)
                .frame(width: 52, height: 52)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("芥子")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(JieziTheme.ink)
            Text("登录后同步快捷指令凭据，用截图和照片快速生成记录。")
                .font(.callout)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var form: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                LoginField(icon: "envelope") {
                    TextField("邮箱", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                }

                Divider()
                    .padding(.leading, 48)

                LoginField(icon: "lock") {
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { signIn() }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.45), lineWidth: 1)
            }

            Button(action: signIn) {
                HStack(spacing: 8) {
                    if appState.isSigningIn {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.forward.circle.fill")
                    }
                    Text(appState.isSigningIn ? "登录中" : "登录")
                        .fontWeight(.semibold)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(JieziTheme.mint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(appState.isSigningIn || email.isEmpty || password.isEmpty ? 0.55 : 1)
            .disabled(appState.isSigningIn || email.isEmpty || password.isEmpty)
        }
    }

    @ViewBuilder
    private var status: some View {
        if let message = appState.authMessage {
            Label(message, systemImage: appState.authMessageIsError ? "exclamationmark.circle" : "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(appState.authMessageIsError ? JieziTheme.coral : JieziTheme.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func signIn() {
        Task {
            await appState.signIn(email: email, password: password)
        }
    }

    private enum Field {
        case email
        case password
    }
}

private struct LoginField<Content: View>: View {
    let icon: String
    let content: Content

    init(icon: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(JieziTheme.muted)
                .frame(width: 22)

            content
                .font(.body)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
    }
}
