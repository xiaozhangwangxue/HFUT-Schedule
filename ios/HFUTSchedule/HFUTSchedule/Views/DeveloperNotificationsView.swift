import SwiftUI

struct DeveloperNotificationsView: View {
    @State private var notifications: [CampusCloudNotification] = []
    @State private var readIDs: Set<Int> = Set(UserDefaults.standard.array(forKey: "readDeveloperNotifications") as? [Int] ?? [])

    var body: some View {
        List {
            if notifications.isEmpty { ContentUnavailableView("暂无开发者通知", systemImage: "bell") }
            ForEach(notifications.sorted { $0.id > $1.id }) { item in
                DisclosureGroup {
                    Text(item.info).textSelection(.enabled)
                    if !item.remark.isEmpty { Text(item.remark).font(.caption).foregroundStyle(.secondary) }
                    if let url = item.url { AppNavigationLink("打开详情") { PortalWebView(url: url) } }
                    Button(readIDs.contains(item.id) ? "标为未读" : "标为已读") { toggle(item.id) }
                } label: {
                    Label(item.title, systemImage: readIDs.contains(item.id) ? "envelope.open" : "envelope.badge")
                }
            }
        }
        .navigationTitle("开发者通知")
        .toolbar { Button("全部已读") { readIDs.formUnion(notifications.map(\.id)); persist() } }
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    private func load(force: Bool = false) async {
        await CampusCloudConfigStore.shared.refreshIfNeeded(force: force)
        notifications = CampusCloudConfigStore.shared.notifications
    }

    private func toggle(_ id: Int) {
        if readIDs.contains(id) { readIDs.remove(id) } else { readIDs.insert(id) }
        persist()
    }

    private func persist() { UserDefaults.standard.set(Array(readIDs), forKey: "readDeveloperNotifications") }
}
