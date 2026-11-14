import SwiftUI
import UIKit
import XCTest
@testable import HFUTSchedule

/// Exercise real SwiftUI layout proposals while the same hosting controller
/// resizes; no device-name, screen-bounds or orientation assumption is needed.
@MainActor
final class DuoLayoutTests: XCTestCase {
    func testGridReflowsInPlaceAndPreservesStateWhenWindowExpandsAndContracts() throws {
        let recorder = GridFrameRecorder()
        let host = UIHostingController(rootView: GridResizeProbe(recorder: recorder))
        let container = try makeContainer(host)
        defer { container.isHidden = true }

        resize(host, width: 320, recorder: recorder)
        let foldedColumns = firstRowCount(recorder.frames)
        assertFramesFit(recorder.frames, width: 320)

        resize(host, width: 900, recorder: recorder)
        let expandedColumns = firstRowCount(recorder.frames)
        assertFramesFit(recorder.frames, width: 900)
        XCTAssertGreaterThan(expandedColumns, foldedColumns)

        resize(host, width: 320, recorder: recorder)
        XCTAssertEqual(firstRowCount(recorder.frames), foldedColumns)
        assertFramesFit(recorder.frames, width: 320)
        XCTAssertEqual(recorder.identities.count, 1, "Resizing must preserve the existing SwiftUI view state")
    }

    func testAccessibilityTextUsesReadableColumnsEvenInNarrowWindow() throws {
        let recorder = GridFrameRecorder()
        let host = UIHostingController(rootView: GridResizeProbe(recorder: recorder)
            .environment(\.dynamicTypeSize, .accessibility3))
        let container = try makeContainer(host)
        defer { container.isHidden = true }

        resize(host, width: 240, recorder: recorder)
        XCTAssertEqual(firstRowCount(recorder.frames), 1)
        assertFramesFit(recorder.frames, width: 240)

        resize(host, width: 700, recorder: recorder)
        XCTAssertEqual(firstRowCount(recorder.frames), 2)
        assertFramesFit(recorder.frames, width: 700)
    }

    private func makeContainer<Content: View>(_ host: UIHostingController<Content>) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.isHidden = false
        root.addChild(host)
        root.view.addSubview(host.view)
        host.didMove(toParent: root)
        host.view.autoresizingMask = []
        return window
    }

    private func resize<Content: View>(_ host: UIHostingController<Content>, width: CGFloat, recorder: GridFrameRecorder) {
        recorder.frames = [:]
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 1600)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let deadline = Date().addingTimeInterval(2)
        while recorder.frames.count < 8, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            host.view.layoutIfNeeded()
        }
        XCTAssertEqual(recorder.frames.count, 8)
    }

    private func firstRowCount(_ frames: [Int: CGRect]) -> Int {
        guard let top = frames.values.map(\.minY).min() else { return 0 }
        return frames.values.filter { abs($0.minY - top) < 1 }.count
    }

    private func assertFramesFit(_ frames: [Int: CGRect], width: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        for frame in frames.values {
            XCTAssertGreaterThan(frame.width, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.minX, -1, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, width + 1, file: file, line: line)
        }
    }
}

@MainActor
private final class GridFrameRecorder {
    var frames: [Int: CGRect] = [:]
    var identities = Set<UUID>()
}

private struct GridResizeProbe: View {
    let recorder: GridFrameRecorder
    @State private var identity = UUID()

    var body: some View {
        CampusAdaptiveGrid {
            ForEach(0..<8, id: \.self) { index in
                Text("校园服务 \(index)")
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { record(index, frame: proxy.frame(in: .named("resize-grid"))) }
                                .onChange(of: proxy.frame(in: .named("resize-grid"))) { _, frame in record(index, frame: frame) }
                        }
                    }
            }
        }
        .coordinateSpace(name: "resize-grid")
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func record(_ index: Int, frame: CGRect) {
        recorder.frames[index] = frame
        recorder.identities.insert(identity)
    }
}
