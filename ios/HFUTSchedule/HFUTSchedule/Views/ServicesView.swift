import SwiftUI

struct ServicesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var shortcutFeature: CampusFeature?
    @State private var serviceOrder: [Int] = []
    @State private var hiddenServiceIDs: Set<Int> = []
    @State private var showingEditor = false

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var filtered: [CampusFeature] {
        orderedFeatures.filter { feature in
            let text = "\(feature.title) \(feature.subtitle) \(feature.category.rawValue)"
            let matchesQuery = query.isEmpty || text.localizedCaseInsensitiveContains(query)
            return matchesQuery && (!query.isEmpty || !hiddenServiceIDs.contains(feature.id))
        }
    }

    private var orderedFeatures: [CampusFeature] {
        let byID = Dictionary(uniqueKeysWithValues: FeatureCatalog.all.map { ($0.id, $0) })
        let known = serviceOrder.compactMap { byID[$0] }
        let knownIDs = Set(known.map(\.id))
        return known + FeatureCatalog.all.filter { !knownIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(filtered) { feature in
                    SourceAnchoredNavigationLink(sourceID: "service-\(feature.id)") {
                        FeatureDetailView(feature: feature)
                    } label: {
                        CompactFeatureTile(feature: feature)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("查询中心")
        .searchable(text: $query, prompt: "搜索 \(FeatureCatalog.all.count) 项校园服务")
        .toolbar {
            Button("编辑", systemImage: "pencil") { showingEditor = true }
        }
        .sheet(isPresented: $showingEditor, onDismiss: persistServiceLayout) {
            NavigationStack {
                List {
                    ForEach(orderedFeatures) { feature in
                        HStack(spacing: 12) {
                            Image(systemName: feature.systemImage).frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(feature.title)
                                Text(feature.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("显示", isOn: visibilityBinding(for: feature.id)).labelsHidden()
                        }
                    }
                    .onMove(perform: moveServices)
                }
                .environment(\.editMode, .constant(.active))
                .navigationTitle("编辑校园服务")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("恢复默认") {
                            serviceOrder = FeatureCatalog.all.map(\.id)
                            hiddenServiceIDs = []
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { persistServiceLayout(); showingEditor = false }
                    }
                }
            }
        }
        .navigationDestination(isPresented: shortcutFeatureBinding) {
            if let shortcutFeature {
                FeatureDetailView(feature: shortcutFeature)
            }
        }
        .onAppear { loadServiceLayout(); consumeShortcutFeature() }
        .onChange(of: appState.pendingFeatureID) { _, _ in consumeShortcutFeature() }
    }

    private var shortcutFeatureBinding: Binding<Bool> {
        Binding(
            get: { shortcutFeature != nil },
            set: { if !$0 { shortcutFeature = nil } }
        )
    }

    private func consumeShortcutFeature() {
        if let feature = appState.consumePendingFeature() {
            shortcutFeature = feature
        }
    }

    private func visibilityBinding(for id: Int) -> Binding<Bool> {
        Binding(
            get: { !hiddenServiceIDs.contains(id) },
            set: { visible in
                if visible { hiddenServiceIDs.remove(id) }
                else { hiddenServiceIDs.insert(id) }
            }
        )
    }

    private func moveServices(from offsets: IndexSet, to destination: Int) {
        var ids = orderedFeatures.map(\.id)
        ids.move(fromOffsets: offsets, toOffset: destination)
        serviceOrder = ids
    }

    private func loadServiceLayout() {
        if let ids = UserDefaults.standard.array(forKey: "service-order") as? [Int] { serviceOrder = ids }
        else { serviceOrder = FeatureCatalog.all.map(\.id) }
        if let ids = UserDefaults.standard.array(forKey: "hidden-services") as? [Int] { hiddenServiceIDs = Set(ids) }
    }

    private func persistServiceLayout() {
        UserDefaults.standard.set(orderedFeatures.map(\.id), forKey: "service-order")
        UserDefaults.standard.set(Array(hiddenServiceIDs), forKey: "hidden-services")
    }

}

private struct CompactFeatureTile: View {
    let feature: CampusFeature

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: feature.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(feature.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(feature.subtitle)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .contentShape(Rectangle())
        .adaptiveGlass(cornerRadius: 10, tint: AppTheme.accent.opacity(0.025), interactive: true)
        .accessibilityElement(children: .combine)
    }
}
