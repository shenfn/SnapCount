import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var mode: AuthMode = .signIn
    @State private var acceptedTerms = false
    @State private var legalDocument: LegalDocumentKind?
    @FocusState private var focusedField: Field?

    var body: some View {
        ZStack {
            JieziPageBackground()

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
        .sheet(item: $legalDocument) { document in
            NavigationStack { LegalDocumentView(kind: document) }
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
            Picker("账号操作", selection: $mode) {
                ForEach(AuthMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

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
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.45), lineWidth: 1)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if appState.isSigningIn {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.forward.circle.fill")
                    }
                    Text(appState.isSigningIn ? "处理中" : mode.actionTitle)
                        .fontWeight(.semibold)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(JieziTheme.mint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(canSubmit ? 1 : 0.55)
            .disabled(!canSubmit)

            if mode == .signUp {
                legalConsent
            }

            Text(mode == .signIn ? "还没有账号？切换到注册即可创建。" : "密码至少 6 位。注册即表示你同意芥子的隐私政策与服务协议。")
                .font(.footnote)
                .foregroundStyle(JieziTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var canSubmit: Bool {
        !appState.isSigningIn
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= 6
            && (mode == .signIn || acceptedTerms)
    }

    private var legalConsent: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $acceptedTerms)
                .labelsHidden()
                .tint(JieziTheme.mint)
            Text("我已阅读并同意")
                .font(.footnote)
                .foregroundStyle(JieziTheme.muted)
            Button("服务协议") { legalDocument = .terms }
                .font(.footnote.weight(.semibold))
            Text("和")
                .font(.footnote)
                .foregroundStyle(JieziTheme.muted)
            Button("隐私政策") { legalDocument = .privacy }
                .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func submit() {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            switch mode {
            case .signIn:
                await appState.signIn(email: cleanEmail, password: password)
            case .signUp:
                await appState.signUp(email: cleanEmail, password: password)
            }
        }
    }

    private enum AuthMode: String, CaseIterable, Identifiable {
        case signIn
        case signUp

        var id: String { rawValue }
        var title: String { self == .signIn ? "登录" : "注册" }
        var actionTitle: String { self == .signIn ? "登录" : "创建账号" }
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
