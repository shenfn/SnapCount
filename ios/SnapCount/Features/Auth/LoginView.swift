import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var mode: AuthMode = .signIn
    @State private var acceptedTerms = false
    @State private var acceptedSensitiveData = false
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

    @ViewBuilder
    private var form: some View {
        if appState.isHandlingAuthCallback {
            callbackPanel
        } else if appState.isPasswordRecovery {
            recoveryForm
        } else if appState.isAwaitingEmailConfirmation {
            confirmationPanel
        } else {
            standardForm
        }
    }

    private var standardForm: some View {
        VStack(spacing: 14) {
            if mode != .resetRequest {
                Picker("账号操作", selection: $mode) {
                    Text(AuthMode.signIn.title).tag(AuthMode.signIn)
                    Text(AuthMode.signUp.title).tag(AuthMode.signUp)
                }
                .pickerStyle(.segmented)
            } else {
                Text("找回密码")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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

                if mode != .resetRequest {
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

            if mode == .signIn {
                HStack {
                    Text("还没有账号？切换到注册即可创建。")
                    Spacer()
                    Button("忘记密码") { mode = .resetRequest }
                        .font(.footnote.weight(.semibold))
                }
                .font(.footnote)
                .foregroundStyle(JieziTheme.muted)
            } else if mode == .resetRequest {
                HStack {
                    Text("想起密码了？")
                    Button("返回登录") { mode = .signIn }
                        .font(.footnote.weight(.semibold))
                }
                .font(.footnote)
                .foregroundStyle(JieziTheme.muted)
            } else {
                Text("密码至少 6 位。注册即表示你同意芥子的隐私政策与服务协议。")
                    .font(.footnote)
                    .foregroundStyle(JieziTheme.muted)
            }
        }
    }

    private var recoveryForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置新密码")
                .font(.title3.weight(.semibold))
            Text("此链接只用于修改密码，完成后需要重新登录。")
                .font(.footnote)
                .foregroundStyle(JieziTheme.muted)

            LoginField(icon: "lock") {
                SecureField("新密码（至少 8 位）", text: $password)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .password)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            LoginField(icon: "lock.rotation") {
                SecureField("再次输入新密码", text: $passwordConfirmation)
                    .textContentType(.newPassword)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(action: submit) {
                HStack(spacing: 8) {
                    if appState.isSigningIn { ProgressView().tint(.white) }
                    Image(systemName: "checkmark.circle.fill")
                    Text(appState.isSigningIn ? "处理中" : "更新密码")
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

            Button("取消并返回登录") { appState.returnToLogin() }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(JieziTheme.mint)
                .frame(maxWidth: .infinity)
        }
    }

    private var confirmationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("请确认邮箱后再登录", systemImage: "envelope.badge")
                .font(.headline)
            Text(maskedEmail(appState.confirmationEmail))
                .font(.footnote)
                .foregroundStyle(JieziTheme.muted)
            Button {
                Task { await appState.resendConfirmation() }
            } label: {
                Label(
                    appState.authResendCooldown > 0
                        ? "\(appState.authResendCooldown) 秒后可重发"
                        : appState.isSigningIn ? "发送中" : "重发确认邮件",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(JieziTheme.mint)
            .disabled(appState.isSigningIn || appState.authResendCooldown > 0)
            Button("返回登录") { appState.returnToLogin() }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(JieziTheme.mint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var callbackPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView()
            Text("正在验证安全链接")
                .font(.headline)
            Text("验证完成后才能继续，请不要关闭此页面。")
                .font(.footnote)
                .foregroundStyle(JieziTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var canSubmit: Bool {
        guard !appState.isSigningIn else { return false }
        if appState.isPasswordRecovery {
            return password.count >= 8 && password == passwordConfirmation
        }
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if mode == .resetRequest { return appState.authResendCooldown == 0 }
        return password.count >= 6 && (mode == .signIn || (acceptedTerms && acceptedSensitiveData))
    }

    private var legalConsent: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            Toggle(isOn: $acceptedSensitiveData) {
                Text("我同意处理主动提交的财务、睡眠等敏感数据，并知悉主要数据存储于新加坡、图片会传输至阿里云百炼中国内地接口完成 Qwen 识别。")
                    .font(.footnote)
                    .foregroundStyle(JieziTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(JieziTheme.mint)
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
            if appState.isPasswordRecovery {
                await appState.updatePassword(newPassword: password, confirmation: passwordConfirmation)
                return
            }
            switch mode {
            case .signIn:
                await appState.signIn(email: cleanEmail, password: password)
            case .signUp:
                await appState.signUp(
                    email: cleanEmail,
                    password: password,
                    acceptedTerms: acceptedTerms,
                    acceptedSensitiveData: acceptedSensitiveData
                )
            case .resetRequest:
                await appState.sendPasswordReset(email: cleanEmail)
            }
        }
    }

    private func maskedEmail(_ value: String) -> String {
        let parts = value.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return value }
        let visible = String(parts[0].prefix(2))
        return "\(visible)***@\(parts[1])"
    }

    private enum AuthMode: String, CaseIterable, Identifiable {
        case signIn
        case signUp
        case resetRequest

        var id: String { rawValue }
        var title: String {
            switch self {
            case .signIn: return "登录"
            case .signUp: return "注册"
            case .resetRequest: return "找回密码"
            }
        }
        var actionTitle: String {
            switch self {
            case .signIn: return "登录"
            case .signUp: return "创建账号"
            case .resetRequest: return "发送重置邮件"
            }
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
