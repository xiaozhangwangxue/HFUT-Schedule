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
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $event.kind) {
                        ForEach(CustomEvent.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("标题", text: $event.title)
                    TextField("地点（可选）", text: $event.location)
                    TextField("说明（可选）", text: $event.detail, axis: .vertical)
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
