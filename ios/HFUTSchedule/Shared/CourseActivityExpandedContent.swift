import SwiftUI

/// Shared with layout tests so a long Chinese title is exercised at narrow widths.
struct CourseActivityExpandedContent: View {
    let state: CourseActivityAttributes.ContentState
    var previewProgress: Double? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(state.title).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !state.location.isEmpty { Text(state.location).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            if let previewProgress {
                GeometryReader { proxy in
                    Capsule().fill(.white.opacity(0.2))
                        .overlay(alignment: .leading) { Capsule().fill(.blue).frame(width: proxy.size.width * previewProgress) }
                }.frame(height: 4)
            }
            else { ProgressView(timerInterval: state.start...state.end, countsDown: false).tint(.blue) }
        }.padding(.top, 5)
    }
}
