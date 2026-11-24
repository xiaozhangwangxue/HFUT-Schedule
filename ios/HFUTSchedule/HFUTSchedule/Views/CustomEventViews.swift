import SwiftUI

struct CustomEventsView: View {
    @EnvironmentObject private var store: CustomEventStore
    @State private var editing: CustomEvent?

    var body: some View {
        List {
            if let error = store.storageError { Text(error).foregroundStyle(.red) }
            if store.events.isEmpty {
                ContentUnavailableView("还没有自建日程", systemImage: "calendar.badge.plus")
            }
            ForEach(store.events.sorted { $0.start < $1.start }) { event in
                Button { editing = event } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(event.title).foregroundStyle(.primary)
                        Text(event.end.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        if !event.location.isEmpty { Text(event.location).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .swipeActions {
                    Button("删除", role: .destructive) { store.remove(event.id) }
                    Button("克隆", systemImage: "doc.on.doc") { editing = event.cloned() }.tint(.blue)
                }
            }
        }
        .navigationTitle("自建日程")
        .toolbar {
            Button("添加日程", systemImage: "plus") {
                editing = CustomEvent(title: "", start: Date(), end: Date().addingTimeInterval(3600))
            }.disabled(store.requiresRecovery)
        }
        .sheet(item: $editing) { event in CustomEventEditor(event: event) }
    }
}

struct CustomEventEditor: View {
    @EnvironmentObject private var store: CustomEventStore
    @Environment(\.dismiss) private var dismiss
    @State var event: CustomEvent
    @State private var isClone = false

    private var isNew: Bool { !store.events.contains { $0.id == event.id } }

    var body: some View {
        AppNavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $event.kind) {
                        ForEach(CustomEvent.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("标题", text: $event.title)
                    TextField("地点（可选）", text: $event.location)
                    TextField("说明（可选）", text: $event.detail, axis: .vertical)
                    AppNavigationLink("选择教学楼") { EventBuildingPicker(selection: $event.location) }
                    Menu("选择学习平台") {
                        ForEach(LearningPlatform.presets, id: \.self) { platform in
                            Button(platform) { event.detail = platform }
                        }
                    }
                }
                Section {
                    AppNavigationLink {
                        AIAssistantView(initialQuestion: CustomEventAIPrompt.text(now: Date()))
                    } label: { Label("AI 辅助创建日程", systemImage: "wand.and.stars") }
                    if event.isValid {
                        SingleCalendarExportButton(occurrence: PlatformScheduleOccurrence(id: "event|\(event.id.uuidString)",
                            sourceID: event.id.uuidString, kind: event.kind == .deadline ? .deadline : .event,
                            title: event.title, location: event.location, detail: event.detail, start: event.start, end: event.end))
                    }
                }
                Section("时间") {
                    if event.kind == .event {
                        DatePicker("开始", selection: startBinding)
                        DatePicker("结束", selection: $event.end, in: event.start...)
                    } else {
                        DatePicker("截止时间", selection: $event.end, in: event.start...)
                    }
                }
                if isClone { Text("已复制为新日程，保存后原日程仍保留。").font(.footnote) }
                if let error = store.storageError { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(isNew ? "新建日程" : "编辑日程")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if !isNew {
                        Button("克隆日程", systemImage: "doc.on.doc") { event = event.cloned(); isClone = true }
                    }
                    Button("保存") { store.save(event); if store.storageError == nil { dismiss() } }
                        .disabled(!event.isValid || store.requiresRecovery)
                }
            }
            .onChange(of: event.kind) { _, kind in
                if kind == .deadline { event.start = min(Date(), event.end) }
            }
        }
    }

    private var startBinding: Binding<Date> {
        Binding(get: { event.start }, set: { value in
            let duration = max(0, event.end.timeIntervalSince(event.start))
            event.start = value
            event.end = value.addingTimeInterval(duration)
        })
    }
}

enum CustomEventAIPrompt {
    static func text(now: Date) -> String {
        """
        请帮助我理解并整理日程，可以先询问缺少的信息，最终返回规范JSON：
        {"title":"标题","type":"Schedule或DeadLine","timeParts":[{"dateTime":{"start":"YYYY-MM-DD HH:mm或null","end":"YYYY-MM-DD HH:mm"},"description":"地点、链接或备注，可为null"}]}
        Schedule是有开始和结束的普通线下日程；DeadLine是只关心截止时间的作业/报告，start为null。
        原版日程模板不支持跨天的单次Schedule，如涉及跨天请先说明并询问拆分方式。信息不明确时请询问类型、标题、时间、地点或备注。
        当前时间：\(now.formatted(date: .numeric, time: .shortened))。请先询问我要创建什么日程。
        """
    }
}

private struct EventBuildingPicker: View {
    struct Building: Decodable, Identifiable {
        struct Summary: Decodable { let id: Int; let nameZh: String }
        let building: Summary
        let campus: String
        var id: Int { building.id }
    }
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var buildings: [Building] = []
    @State private var query = ""
    @State private var error: String?
    var body: some View {
        List {
            ForEach(buildings.filter { query.isEmpty || $0.building.nameZh.localizedCaseInsensitiveContains(query) }) { item in
                Button { selection = item.building.nameZh; dismiss() } label: {
                    VStack(alignment: .leading) { Text(item.building.nameZh); Text(item.campus).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("选择教学楼").searchable(text: $query)
            .task {
                do {
                    let url = URL(string: "https://raw.githubusercontent.com/Chiu-xaH/HFUT-Schedule/dev/src/source/building/list.json")!
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
                    buildings = try JSONDecoder().decode([Building].self, from: data)
                } catch { self.error = error.localizedDescription }
            }
    }
}
