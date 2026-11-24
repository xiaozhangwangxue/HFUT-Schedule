import Foundation
import WidgetKit

/// A data update requests an immediate reload. A bounded retry window covers the
/// handoff back to the Home Screen; it never claims control over WidgetKit's renderer.
@MainActor
final class WidgetRefreshCoordinator {
    static let shared = WidgetRefreshCoordinator()

    private let publication: () -> WidgetPublicationStatus?
    private let acknowledged: (WidgetPublicationStatus) -> Bool
    private let reload: () -> Void
    private let sleep: (Duration) async throws -> Void
    private var retryTask: Task<Void, Never>?
    private var generation = UUID()

    init(
        publication: @escaping () -> WidgetPublicationStatus? = { WidgetSnapshotStore.lastSyncStatus },
        acknowledged: @escaping (WidgetPublicationStatus) -> Bool = { WidgetSnapshotStore.acknowledged($0) },
        reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() },
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.publication = publication
        self.acknowledged = acknowledged
        self.reload = reload
        self.sleep = sleep
    }

    deinit { retryTask?.cancel() }

    func requestReload() {
        generation = UUID()
        retryTask?.cancel()
        retryTask = nil
        guard let status = publication(), status.didWrite else { return }
        reload()
        let requestGeneration = generation
        let pause = sleep
        retryTask = Task { [weak self] in
            for delay in [1, 2, 5] {
                do { try await pause(.seconds(delay)) } catch { return }
                guard !Task.isCancelled, let self, self.generation == requestGeneration,
                      let current = self.publication(), current.didWrite,
                      current.revision == status.revision else { return }
                if self.acknowledged(current) { return }
                self.reload()
            }
        }
    }

    /// Called at the App -> Home Screen handoff, without rewriting an unchanged snapshot.
    func requestPendingReload() {
        guard let status = publication(), status.didWrite, !acknowledged(status) else { return }
        reload()
    }
}
