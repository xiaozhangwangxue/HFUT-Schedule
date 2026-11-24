import SwiftUI

struct LoginServiceScopeView: View {
    let mode: AcademicConnectionMode
    let excludesAcademic: Bool
    @State private var networkStatus = "正在检测教务网络…"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(networkStatus, systemImage: "network").font(.caption)
            Text(excludesAcademic
                 ? "本次刷新：信息门户、智慧社区、一卡通与生活缴费、第二课堂。保留原有教务数据。"
                 : "本次刷新：CAS、教务课表/学籍/成绩/考试、UniApp、信息门户、智慧社区、一卡通与生活缴费、第二课堂。")
                .font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
            .padding(.bottom, 6)
            .task(id: mode) { await probe() }
    }

    private func probe() async {
        networkStatus = "正在检测教务网络…"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 7
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (_, response) = try await session.data(from: AcademicPortal.url("for-std/course-table", mode: mode))
            guard !Task.isCancelled else { return }
            if let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
                networkStatus = "\(mode.title)：教务入口可连接"
            } else { networkStatus = "教务入口暂未正常响应，可尝试切换访问方式或跳过教务" }
        } catch {
            guard !Task.isCancelled else { return }
            networkStatus = "教务入口暂不可连接，可尝试 WebVPN 或跳过教务"
        }
    }
}
