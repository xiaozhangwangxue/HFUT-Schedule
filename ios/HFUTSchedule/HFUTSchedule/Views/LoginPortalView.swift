import SwiftUI

struct LoginPortalView: View {
    private let loginURL = URL(string: "https://cas.hfut.edu.cn/cas/login?service=https%3A%2F%2Fone.hfut.edu.cn%2Fhome%2Findex")!

    var body: some View {
        PortalWebView(url: loginURL)
            .safeAreaInset(edge: .bottom) {
                Label("凭据只提交给合肥工业大学统一身份认证", systemImage: "lock.shield.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .adaptiveGlass(cornerRadius: 19)
                    .padding(.bottom, 6)
            }
            .navigationTitle("安全登录")
            .navigationBarTitleDisplayMode(.inline)
    }
}
