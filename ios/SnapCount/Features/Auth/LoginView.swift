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
                VStack(alignment: .leading, spacing: 22) {
                    header
                    form
                    status
                }
                .padding(.horizontal, 22)
                .padding(.top, 64)
                .padding(.bottom, 32)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("芥子")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(JieziTheme.ink)
            Text("登录后，芥子会把快捷指令上传所需凭据安全同步到 Keychain。")
                .font(.body)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var form: some View {
        GlassPanel {
            VStack(spacing: 14) {
                TextField("邮箱", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .textFieldStyle(.roundedBorder)

                SecureField("密码", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { signIn() }
                    .textFieldStyle(.roundedBorder)

                PrimaryActionButton(
                    title: appState.isSigningIn ? "登录中" : "登录",
                    systemImage: "person.crop.circle.badge.checkmark"
                ) {
                    signIn()
                }
                .disabled(appState.isSigningIn || email.isEmpty || password.isEmpty)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let message = appState.authMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(appState.authMessageIsError ? JieziTheme.coral : JieziTheme.muted)
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
