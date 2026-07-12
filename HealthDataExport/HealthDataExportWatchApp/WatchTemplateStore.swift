import Foundation
import Combine

/// Caches the user's workout templates so tapping "开始训练" shows the list
/// instantly. Prefetched at app launch and refreshed whenever the list appears.
@MainActor
final class WatchTemplateStore: ObservableObject {
    static let shared = WatchTemplateStore()

    @Published private(set) var templates: [FitnessTemplateSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    /// Load templates into the cache. Keeps the previous list visible while
    /// refreshing, and only surfaces an error when there's nothing to show.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            templates = try await FitnessAPIClient.templates()
            errorMessage = nil
        } catch {
            if templates.isEmpty { errorMessage = SharedL10n.tr("watch.fitness.templates_load_failed") }
        }
    }
}
