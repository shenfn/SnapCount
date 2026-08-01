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
    @State private var showDeleteAccountConfirmation = false
    @FocusState private var focusedField: Field?

    var body: some View {
        ZStack {
            JieziPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if let receipt = appState.lastAccountDeletionReceipt {
                        accountDeletionReceiptPanel(receipt)
                    }
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
        .alert("提交账户删除请求？", isPresented: $showDeleteAccountConfirmation) {
            Button("删除账户及全部数据", role: .destructive) {
                Task { _ = await appState.deleteAccountFromGate() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("提交后会立即退出登录，并在后台异步删除云端记录、账户流水、AI 识别数据和原图。通常在 24 小时内完成，且无法恢复。")
        }
        .onChange(of: appState.currentUserId) { _, _ in
            resetConsentSelections()
        }
        .onChange(of: appState.requiresAccountConsent) { _, requiresConsent in
            if requiresConsent {
                resetConsentSelections()
            }
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
            Text(headerMessage)
                .font(.callout)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerMessage: String {
        if appState.isAccountAccessBlocked {
            return "账户暂不可用，当前不会加载你的记录。"
        }
        if appState.requiresAccountConsent || appState.isCheckingAccountConsent {
            return "确认当前的数据处理说明后，才会加载你的记录。"
        }
        return "登录后同步快捷指令凭据，用截图和照片快速生成记录。"
    }

    @ViewBuilder
    private var form: some View {
        if appState.isCheckingAccountConsent {
            accountConsentPanel
        } else if appState.isAccountAccessBlocked {
            accountAccessBlockedPanel
        } else if appState.requiresAccountConsent {
            accountConsentPanel
        } else if appState.isHandlingAuthCallback {
            callbackPanel
        } else if appState.isPasswordRecovery {
            recoveryForm
        } else if appState.isAwaitingEmailConfirmation {
            confirmationPanel
        } else {
            standardForm
        }
    }

    private var accountConsentPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if appState.isCheckingAccountConsent {
                ProgressView()
                Text("正在核对账号状态")
                    .font(.headline)
                Text("完成前不会加载你的记录或调用 AI 服务。")
                    .font(.footnote)
                    .foregroundStyle(JieziTheme.muted)
            } else {
                Label("继续使用芥子", systemImage: "hand.raised.fill")
                    .font(.headline)
                    .foregroundStyle(JieziTheme.ink)
                Text("你的记录包含财务、图片、睡眠等私密信息。主要数据存储在 Supabase 新加坡区域；使用图片识别和 AI 联动分析时，必要内容会发送至阿里云百炼 Qwen 当前的中国内地接口。")
                    .font(.footnote)
                    .foregroundStyle(JieziTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                legalConsent

                if let message = appState.accountConsentError {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(JieziTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task {
                        await appState.acceptAccountConsent(
                            acceptedTerms: acceptedTerms,
                            acceptedSensitiveData: acceptedSensitiveData
                        )
                    }
                } label: {
                    HStack(spacing: 8) {
                        if appState.isAcceptingAccountConsent { ProgressView().tint(.white) }
                        Image(systemName: "checkmark.shield.fill")
                        Text(appState.isAcceptingAccountConsent ? "正在确认" : "同意并继续")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(JieziTheme.mint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .opacity(acceptedTerms && acceptedSensitiveData && !appState.isAcceptingAccountConsent ? 1 : 0.55)
                .disabled(!acceptedTerms || !acceptedSensitiveData || appState.isAcceptingAccountConsent)

                HStack {
                    if appState.accountConsentError != nil {
                        Button("重新核对") {
                            Task { await appState.retryAccountConsent() }
                        }
                        .disabled(appState.isCheckingAccountConsent || appState.isAcceptingAccountConsent)
                    }
                    Spacer()
                    Button("退出登录") { appState.signOut() }
                        .disabled(appState.isAcceptingAccountConsent)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(JieziTheme.mint)

                if appState.accountConsentError != nil {
                    Button(role: .destructive) {
                        showDeleteAccountConfirmation = true
                    } label: {
                        Label("删除账户及全部数据", systemImage: "person.crop.circle.badge.xmark")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(JieziTheme.coral)
                    .disabled(appState.isAcceptingAccountConsent || appState.isDeletingAccount)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var accountAccessBlockedPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("账户暂不可用", systemImage: "lock.circle.fill")
                .font(.headline)
                .foregroundStyle(JieziTheme.ink)
            Text(appState.accountAccessBlockedMessage ?? "账户已停用，当前不会加载你的记录或调用 AI 服务。")
                .font(.footnote)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if appState.isDeletingAccount {
                ProgressView("正在提交删除请求")
                    .font(.footnote)
            }

            HStack {
                Button("重新核对") {
                    Task { await appState.retryAccountConsent() }
                }
                .disabled(appState.isCheckingAccountConsent || appState.isDeletingAccount)
                Spacer()
                Button("退出登录") { appState.signOut() }
                    .disabled(appState.isDeletingAccount)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(JieziTheme.mint)

            Button(role: .destructive) {
                showDeleteAccountConfirmation = true
            } label: {
                Label("删除账户及全部数据", systemImage: "person.crop.circle.badge.xmark")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(JieziTheme.coral)
            .disabled(appState.isDeletingAccount)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func accountDeletionReceiptPanel(
        _ receipt: NativeAccountDeletionResult
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                receipt.isCompleted ? "账户删除已完成" : "账户删除处理中",
                systemImage: receipt.isCompleted ? "checkmark.shield.fill" : "clock.fill"
            )
            .font(.headline)
            .foregroundStyle(receipt.isCompleted ? JieziTheme.mint : JieziTheme.ink)

            Text(receipt.displayMessage)
                .font(.footnote)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button("关闭回执") { appState.dismissAccountDeletionReceipt() }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(JieziTheme.mint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            Button("更换邮箱") { appState.changeConfirmationEmail() }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(JieziTheme.mint)
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
        if appState.lastAccountDeletionReceipt == nil,
           let message = appState.authMessage {
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

    private func resetConsentSelections() {
        acceptedTerms = false
        acceptedSensitiveData = false
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
