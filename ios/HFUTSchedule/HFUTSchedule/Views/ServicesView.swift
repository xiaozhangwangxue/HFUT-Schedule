import SwiftUI

struct ServicesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var shortcutFeature: CampusFeature?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var filtered: [CampusFeature] {
        FeatureCatalog.all.filter { feature in
            let text = "\(feature.title) \(feature.subtitle) \(feature.category.rawValue)"
            let matchesQuery = query.isEmpty || text.localizedCaseInsensitiveContains(query)
            return matchesQuery
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(filtered) { feature in
                    NavigationLink(value: feature) {
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
        .searchable(text: $query, prompt: "搜索 48 项校园服务")
        .navigationDestination(for: CampusFeature.self) { feature in
            FeatureDetailView(feature: feature)
        }
        .navigationDestination(isPresented: shortcutFeatureBinding) {
            if let shortcutFeature {
                FeatureDetailView(feature: shortcutFeature)
            }
        }
        .onAppear(perform: consumeShortcutFeature)
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

}

private struct CompactFeatureTile: View {
    let feature: CampusFeature

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: feature.systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 25)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(feature.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .contentShape(Rectangle())
        .adaptiveGlass(cornerRadius: 13, tint: AppTheme.accent.opacity(0.025), interactive: true)
        .accessibilityElement(children: .combine)
    }
}
