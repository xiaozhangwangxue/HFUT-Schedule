import SwiftUI
import UIKit

@MainActor
struct NativeCASLoginView: View {
    let mode: AcademicConnectionMode
    let onAuthenticated: ([HTTPCookie], String, String) -> Void
    let onPreparationFailure: (Error) -> Void

    @AppStorage("academicUsername") private var username = ""
    @AppStorage("enableOcrCaptcha") private var enableOcrCaptcha = true
    @State private var password = ""
    @StateObject private var captchaAutofill: CASCaptchaAutofillModel
    @State private var preparation: CASLoginPreparation?
    @State private var errorMessage: String?
    @State private var operation: LoginOperation?
    @State private var operationID: UUID?
    @State private var operationTask: Task<Void, Never>?
    @State private var isVisible = false

    private let client: CASLoginClient
    private enum LoginOperation { case prepare, refreshCaptcha, login }
    private var isNetworkBusy: Bool { operation != nil }
    private var isPreparing: Bool { operation == .prepare }
    private var isLoggingIn: Bool { operation == .login }
    private var isRefreshingCaptcha: Bool { operation == .refreshCaptcha }

    init(
        mode: AcademicConnectionMode,
        onAuthenticated: @escaping ([HTTPCookie], String, String) -> Void,
        onPreparationFailure: @escaping (Error) -> Void = { _ in },
        recognizer: any CASCaptchaRecognizing = CASCaptchaRecognizer.shared,
        initialPreparation: CASLoginPreparation? = nil
    ) {
        self.mode = mode
        self.onAuthenticated = onAuthenticated
        self.onPreparationFailure = onPreparationFailure
        client = CASLoginClient(mode: mode)
        _captchaAutofill = StateObject(wrappedValue: CASCaptchaAutofillModel(recognizer: recognizer))
        _preparation = State(initialValue: initialPreparation)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    GlassIcon(systemName: "lock.shield.fill", tint: AppTheme.cyan, size: 68)
                    Text("CAS 统一身份认证")
                        .font(.title2.bold())
                    Text(mode == .direct
                         ? "使用与 Android 原版一致的原生 CAS 请求与 AES 加密流程"
                         : "使用原版 WebVPN 虚拟 Cookie 与代理教务链路")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 8)

                VStack(spacing: 14) {
                    TextField("学号", text: $username)
                        .textContentType(.username)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    SecureField("信息门户密码", text: $password)
                        .textContentType(.password)
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if preparation?.needsCaptcha == true {
                        HStack(spacing: 12) {
                            TextField("验证码", text: Binding(
                                get: { captchaAutofill.text },
                                set: { captchaAutofill.userEdited($0) }
                            ))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            captchaImage
                        }
                        Toggle("图片验证码自动填充", isOn: $enableOcrCaptcha)
                        HStack(alignment: .top, spacing: 8) {
                            if captchaAutofill.isRecognizing { ProgressView().controlSize(.small) }
                            if let status = captchaAutofill.statusText {
                                Text(status).font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if enableOcrCaptcha {
                                Button("重新识别") { captchaAutofill.retry() }
                                    .font(.caption)
                                    .disabled(!captchaAutofill.canRetry || isNetworkBusy)
                            }
                        }
                    }
                }
                .disabled(isNetworkBusy)
                .padding(18)
                .adaptiveGlass(cornerRadius: 26)

                Button {
                    startOperation(.login)
                } label: {
                    HStack {
                        if isLoggingIn { ProgressView().tint(.white) }
                        Text(isLoggingIn ? "正在登录…" : "登录并同步全部教务数据")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(preparation == nil || isNetworkBusy ||
                          (preparation?.needsCaptcha == true && captchaAutofill.text.isEmpty && captchaAutofill.isRecognizing))

                Button("刷新登录参数与验证码", systemImage: "arrow.clockwise") {
                    startOperation(.prepare)
                }
                .disabled(isNetworkBusy)

                if isPreparing {
                    ProgressView("正在从 CAS 获取登录参数…")
                        .font(.footnote)
                }
            }
            .padding(18)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .task {
            isVisible = true
            captchaAutofill.activate(enabled: enableOcrCaptcha)
            if let current = preparation {
                captchaAutofill.setImage(current.needsCaptcha ? current.captchaImageData : nil)
            }
            // A previous request may still be unwinding cancellation after a navigation change.
            // Wait for it before allowing the same client to prepare a fresh CAS session.
            if let previous = operationTask { await previous.value }
            guard !Task.isCancelled, isVisible else { return }
            if preparation == nil {
                startOperation(.prepare)
                if let current = operationTask { await current.value }
            }
        }
        .onChange(of: enableOcrCaptcha) { _, enabled in captchaAutofill.setEnabled(enabled) }
        .onDisappear {
            isVisible = false
            operationTask?.cancel()
            captchaAutofill.deactivate()
            captchaAutofill.setImage(nil)
            preparation = nil
        }
        .alert("登录失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("重新获取") { startOperation(.prepare) }
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var captchaImage: some View {
        if let data = preparation?.captchaImageData, let image = UIImage(data: data) {
            Button { startOperation(.refreshCaptcha) } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 108, height: 48)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("刷新验证码")
        } else {
            Button(isRefreshingCaptcha ? "正在刷新…" : "刷新验证码") { startOperation(.refreshCaptcha) }
                .frame(width: 108, height: 48)
        }
    }

    /// One tracked task owns the CAS client's mutable session headers at a time.
    private func startOperation(_ requested: LoginOperation) {
        guard isVisible, !isNetworkBusy else { return }
        let id = UUID()
        operation = requested
        operationID = id
        operationTask = Task { @MainActor in
            defer {
                if operationID == id {
                    operation = nil
                    operationID = nil
                    operationTask = nil
                }
            }
            guard !Task.isCancelled, isVisible else { return }
            switch requested {
            case .prepare: await prepare()
            case .refreshCaptcha: await reloadCaptcha()
            case .login: await logIn()
            }
        }
    }

    private func prepare() async {
        errorMessage = nil
        preparation = nil
        captchaAutofill.setImage(nil)
        do {
            let result = try await client.prepare()
            guard !Task.isCancelled, isVisible else { return }
            preparation = result
            captchaAutofill.setImage(result.needsCaptcha ? result.captchaImageData : nil)
        } catch {
            guard !Task.isCancelled, isVisible else { return }
            preparation = nil
            errorMessage = error.localizedDescription
            onPreparationFailure(error)
        }
    }

    private func reloadCaptcha() async {
        // Capture the execution before suspension. Never pair an old request's image
        // with a later preparation, and never overlap challenge-generating requests.
        guard let old = preparation, old.needsCaptcha else { return }
        captchaAutofill.setImage(nil)
        preparation = CASLoginPreparation(execution: old.execution, needsCaptcha: true, captchaImageData: nil)
        do {
            let data = try await client.fetchCaptcha()
            guard !Task.isCancelled, isVisible, preparation?.execution == old.execution else { return }
            preparation = CASLoginPreparation(execution: old.execution, needsCaptcha: old.needsCaptcha, captchaImageData: data)
            captchaAutofill.setImage(data)
        } catch {
            guard !Task.isCancelled, isVisible else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func logIn() async {
        guard let currentPreparation = preparation else { return }
        captchaAutofill.cancelPendingRecognition()
        let submittedCaptcha = captchaAutofill.text
        let submittedUsername = username
        let submittedPassword = password
        if currentPreparation.needsCaptcha && submittedCaptcha.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "请输入图片验证码"
            return
        }
        errorMessage = nil
        do {
            let cookies = try await client.login(
                username: submittedUsername,
                password: submittedPassword,
                captcha: submittedCaptcha,
                execution: currentPreparation.execution
            )
            guard !Task.isCancelled, isVisible else { return }
            onAuthenticated(cookies, submittedUsername, submittedPassword)
            password = ""
        } catch {
            guard !Task.isCancelled, isVisible else { return }
            preparation = nil
            captchaAutofill.setImage(nil)
            errorMessage = error.localizedDescription
        }
    }
}
