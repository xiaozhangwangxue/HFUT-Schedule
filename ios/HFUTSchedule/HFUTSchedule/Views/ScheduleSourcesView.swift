import SwiftUI

struct ScheduleSourcesView: View {
    @EnvironmentObject private var schedule: ScheduleStore
    @StateObject private var coordinator = ScheduleSourceCoordinator.shared
    @AppStorage(AppSettingsKey.defaultCourseSource) private var sourceID = "academic"
    @State private var friends: [ScheduleFriend] = []
    @State private var applications: [ScheduleFriend] = []
    @State private var studentID = ""
    @State private var busy = false
    @State private var status: String?

    var body: some View {
        Form {
            Section("我的课表") {
                Picker("默认来源", selection: $sourceID) {
                    ForEach(ScheduleSource.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Text((ScheduleSource(rawValue: sourceID) ?? .academic).detail).font(.caption).foregroundStyle(.secondary)
                Button("切回自己的课表并刷新") {
                    coordinator.activate(source, store: schedule)
                    Task { await coordinator.refresh(source, store: schedule) }
                }.disabled(coordinator.isLoading)
                if let message = coordinator.message { Text(message).font(.caption).textSelection(.enabled) }
            }
            Section("申请好友课表") {
                TextField("对方学号", text: $studentID).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("发送查看申请") { mutate(path: "api/business/coursefriendapply/add", body: ["applyUserId": studentID]) }
                    .disabled(studentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                Text("对方同意后方可查看其课表。好友数据仅保存在本机缓存中。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("已获授权的好友") {
                if friends.isEmpty { Text("暂无好友，或尚未读取").foregroundStyle(.secondary) }
                ForEach(friends) { friend in
                    Button {
                        coordinator.activate(.community, store: schedule, friend: friend.studentID)
                        Task { await coordinator.refresh(.community, store: schedule) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) { Text(friend.name); Text(friend.studentID).font(.caption) }
                            Spacer()
                            if coordinator.friendID == friend.studentID { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Section("收到的申请") {
                Button("开启好友课表授权功能") { mutate(path: "api/business/sys/user/usingfriendcourse", body: ["friendEnabled": 1]) }
                ForEach(applications) { application in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(application.name) · \(application.studentID)")
                        HStack {
                            Button("同意") { decide(application, accept: true) }.buttonStyle(.borderedProminent)
                            Button("拒绝", role: .destructive) { decide(application, accept: false) }.buttonStyle(.bordered)
                        }.disabled(busy)
                    }
                }
                Text("同意后，对方可查看你的课表。原版暂未实现删除好友，此处也不提供无效删除按钮。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if busy { ProgressView() }
            if let status { Section { Text(status).font(.footnote).textSelection(.enabled) } }
        }
        .navigationTitle("课表来源与好友")
        .toolbar { Button("刷新好友", systemImage: "arrow.clockwise") { Task { await loadFriends() } }.disabled(busy) }
        .task { await loadFriends() }
        .onChange(of: sourceID) { _, _ in
            coordinator.activate(source, store: schedule)
            Task { await coordinator.refresh(source, store: schedule) }
        }
    }

    private var source: ScheduleSource { ScheduleSource(rawValue: sourceID) ?? .academic }
    private func loadFriends() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let client = OfficialCampusAPIClient.shared
            let own = try ScheduleSourceParser.object(await client.communityAuthorizedData(path: "api/business/coursefriendapply/list"))
            guard own["success"] as? Bool != false else { throw OfficialCampusAPIError.invalidData(own["message"] as? String ?? "好友列表暂未读取成功") }
            friends = ScheduleFriend.parse(own["result"], application: false)
            let incoming = try ScheduleSourceParser.object(await client.communityAuthorizedData(path: "api/business/coursefriendapply/apgelist?pageSize=30&applyUsername=&pageNo=1"))
            applications = ScheduleFriend.parse((incoming["result"] as? [String: Any])?["records"], application: true)
            status = nil
        } catch { status = error.localizedDescription }
    }
    private func decide(_ request: ScheduleFriend, accept: Bool) {
        mutate(path: "api/business/coursefriendapply/edit", body: ["id": request.id, "status": accept ? 1 : 0])
    }
    private func mutate(path: String, body: [String: Any]) {
        busy = true
        Task { @MainActor in
            do {
                let data = try await OfficialCampusAPIClient.shared.communityAuthorizedData(path: path, method: "POST", body: JSONSerialization.data(withJSONObject: body))
                let reply = try ScheduleSourceParser.object(data)
                guard reply["success"] as? Bool != false else { throw OfficialCampusAPIError.invalidData(reply["message"] as? String ?? "操作未完成") }
                let notice = reply["message"] as? String ?? "操作已完成"
                busy = false
                await loadFriends()
                status = notice
            } catch { status = error.localizedDescription; busy = false }
        }
    }
}

private struct ScheduleFriend: Identifiable {
    let id: String
    let studentID: String
    let name: String
    static func parse(_ value: Any?, application: Bool) -> [Self] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            guard let studentID = item[application ? "applyUserId" : "userId"] as? String else { return nil }
            return Self(id: item["id"] as? String ?? studentID, studentID: studentID,
                name: item[application ? "applyUsername" : "realname"] as? String ?? studentID)
        }
    }
}
