import SwiftUI
import UIKit

struct NativeCASLoginView: View {
    let mode: AcademicConnectionMode
    let onAuthenticated: ([HTTPCookie], String, String) -> Void
    let onPreparationFailure: (Error) -> Void

    @AppStorage("academicUsername") private var username = ""
    @State private var password = ""
    @State private var captcha = ""
    @State private var preparation: CASLoginPreparation?
    @State private var isPreparing = false
    @State private var isLoggingIn = false
    @State private var errorMessage: String?

    private let client: CASLoginClient

    init(
        mode: AcademicConnectionMode,
        onAuthenticated: @escaping ([HTTPCookie], String, String) -> Void,
        onPreparationFailure: @escaping (Error) -> Void = { _ in }
    ) {
        self.mode = mode
        self.onAuthenticated = onAuthenticated
        self.onPreparationFailure = onPreparationFailure
        client = CASLoginClient(mode: mode)
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
                            TextField("验证码", text: $captcha)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            captchaImage
                        }
                    }
                }
                .padding(18)
                .adaptiveGlass(cornerRadius: 26)

                Button {
                    Task { await logIn() }
                } label: {
                    HStack {
                        if isLoggingIn { ProgressView().tint(.white) }
                        Text(isLoggingIn ? "正在登录…" : "登录并同步全部教务数据")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(preparation == nil || isPreparing || isLoggingIn)

                Button("刷新登录参数与验证码", systemImage: "arrow.clockwise") {
                    Task { await prepare() }
                }
                .disabled(isPreparing || isLoggingIn)

                if isPreparing {
                    ProgressView("正在从 CAS 获取登录参数…")
                        .font(.footnote)
                }
            }
            .padding(18)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .task { if preparation == nil { await prepare() } }
        .alert("登录失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("重新获取") { Task { await prepare() } }
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var captchaImage: some View {
        if let data = preparation?.captchaImageData, let image = UIImage(data: data) {
            Button { Task { await reloadCaptcha() } } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 108, height: 48)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("刷新验证码")
        } else {
            Button("刷新验证码") { Task { await reloadCaptcha() } }
                .frame(width: 108, height: 48)
        }
    }

    @MainActor
    private func prepare() async {
        isPreparing = true
        errorMessage = nil
        do {
            preparation = try await client.prepare()
            captcha = ""
        } catch {
            preparation = nil
            errorMessage = error.localizedDescription
            onPreparationFailure(error)
        }
        isPreparing = false
    }

    @MainActor
    private func reloadCaptcha() async {
        do {
            let data = try await client.fetchCaptcha()
            guard let old = preparation else { return }
            preparation = CASLoginPreparation(execution: old.execution, needsCaptcha: old.needsCaptcha, captchaImageData: data)
            captcha = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func logIn() async {
        guard let currentPreparation = preparation else { return }
        if currentPreparation.needsCaptcha && captcha.isEmpty {
            errorMessage = "请输入图片验证码"
            return
        }
        isLoggingIn = true
        errorMessage = nil
        do {
            let cookies = try await client.login(
                username: username,
                password: password,
                captcha: captcha,
                execution: currentPreparation.execution
            )
            onAuthenticated(cookies, username, password)
            password = ""
        } catch {
            preparation = nil
            errorMessage = error.localizedDescription
        }
        isLoggingIn = false
    }
}
