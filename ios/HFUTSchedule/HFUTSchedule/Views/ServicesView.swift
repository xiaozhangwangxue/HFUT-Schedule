import SwiftUI

struct ServicesView: View {
    @State private var query = ""
    @State private var category: FeatureCategory?

    private var filtered: [CampusFeature] {
        FeatureCatalog.all.filter { feature in
            let matchesCategory = category == nil || feature.category == category
            let text = "\(feature.title) \(feature.subtitle) \(feature.category.rawValue)"
            let matchesQuery = query.isEmpty || text.localizedCaseInsensitiveContains(query)
            return matchesCategory && matchesQuery
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                categoryPicker

                ForEach(groupedCategories, id: \.0) { category, features in
                    VStack(spacing: 10) {
                        SectionHeader(title: category.rawValue, subtitle: "\(features.count) 项服务")
                        ForEach(features) { feature in
                            NavigationLink(value: feature) {
                                FeatureRow(feature: feature)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("校园服务")
        .searchable(text: $query, prompt: "搜索 48 项校园服务")
        .navigationDestination(for: CampusFeature.self) { feature in
            FeatureDetailView(feature: feature)
        }
    }

    private var groupedCategories: [(FeatureCategory, [CampusFeature])] {
        FeatureCategory.allCases.compactMap { value in
            let items = filtered.filter { $0.category == value }
            return items.isEmpty ? nil : (value, items)
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton("全部", value: nil)
                ForEach(FeatureCategory.allCases) { value in
                    categoryButton(value.rawValue, value: value)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func categoryButton(_ title: String, value: FeatureCategory?) -> some View {
        Button {
            withAnimation(.snappy) { category = value }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(category == value ? .white : .primary)
                .padding(.horizontal, 15)
                .frame(height: 40)
                .background {
                    if category == value {
                        Capsule().fill(AppTheme.accent)
                    }
                }
                .adaptiveGlass(cornerRadius: 20, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

private struct FeatureRow: View {
    let feature: CampusFeature

    var body: some View {
        HStack(spacing: 14) {
            GlassIcon(systemName: feature.systemImage, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(feature.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
        .adaptiveGlass(cornerRadius: 22, interactive: true)
        .accessibilityElement(children: .combine)
    }
}
