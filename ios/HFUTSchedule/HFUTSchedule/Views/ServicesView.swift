import SwiftUI

struct ServicesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @Environment(\.platformNavigationScope) private var navigationScope
    @State private var serviceOrder: [Int] = []
    @State private var hiddenServiceIDs: Set<Int> = []
    @State private var showingEditor = false

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
            CampusAdaptiveGrid {
                ForEach(filtered) { feature in
                    SourceAnchoredNavigationLink(sourceID: "service-\(feature.id)", title: feature.title) {
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
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("查询中心")
        .searchable(text: $query, prompt: "搜索 \(FeatureCatalog.all.count) 项校园服务")
        .toolbar {
            Button("编辑", systemImage: "pencil") { showingEditor = true }
        }
        .sheet(isPresented: $showingEditor, onDismiss: persistServiceLayout) {
            AppNavigationStack {
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
        .onAppear { loadServiceLayout(); consumeShortcutFeature() }
        .onChange(of: appState.pendingFeatureID) { _, _ in consumeShortcutFeature() }
    }

    private func consumeShortcutFeature() {
        guard let feature = appState.consumePendingFeature() else { return }
        let coordinator = PlatformNavigationCoordinator.shared
        let route = coordinator.register(id: UUID(), title: feature.title) { FeatureDetailView(feature: feature) }
        coordinator.setPath([route], scope: navigationScope ?? "services")
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
        if let ids = UserDefaults.standard.array(forKey: "service-order") as? [Int], ids != serviceOrder { serviceOrder = ids }
        else if serviceOrder.isEmpty { serviceOrder = FeatureCatalog.all.map(\.id) }
        if let ids = UserDefaults.standard.array(forKey: "hidden-services") as? [Int], Set(ids) != hiddenServiceIDs { hiddenServiceIDs = Set(ids) }
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
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(feature.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .contentShape(Rectangle())
        .adaptiveGlass(cornerRadius: 10, tint: AppTheme.accent.opacity(0.025), interactive: true)
        .accessibilityElement(children: .combine)
    }
}
