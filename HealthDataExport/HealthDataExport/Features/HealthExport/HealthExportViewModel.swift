import Combine
import Foundation
import SwiftUI

@MainActor
final class HealthExportViewModel: ObservableObject {
    @Published var selectedConfigurationID: UUID?
    @Published var draft = ExportConfiguration()
    @Published var isSending = false
    @Published var isGeneratingPreview = false
    @Published var statusMessage = ""
    @Published var previewPayload: HealthExportPayload?
    @Published var previewSummary = ""
    @Published var previewJSON = ""

    let store: ConfigurationStore

    init(store: ConfigurationStore) {
        self.store = store
        reloadSelectedConfiguration()
    }

    func reloadSelectedConfiguration() {
        if let selectedConfigurationID,
           let selected = store.configuration(id: selectedConfigurationID) {
            draft = selected
        } else {
            select(store.configurations.first ?? store.addConfiguration())
        }
    }

    func select(_ configuration: ExportConfiguration) {
        selectedConfigurationID = configuration.id
        draft = configuration
    }

    func draftDidChange(_ newValue: ExportConfiguration) {
        store.update(newValue)
        clearPreview()
    }

    func metricBinding(_ metric: HealthMetric) -> Binding<Bool> {
        Binding {
            self.draft.selectedMetricIDs.contains(metric.id)
        } set: { isEnabled in
            if isEnabled {
                self.draft.selectedMetricIDs.insert(metric.id)
            } else {
                self.draft.selectedMetricIDs.remove(metric.id)
            }
        }
    }

    func clearPreview() {
        previewPayload = nil
        previewSummary = ""
        previewJSON = ""
    }

    func generatePreview() async {
        isGeneratingPreview = true
        statusMessage = ""
        do {
            let exporter = HealthKitExporter()
            statusMessage = L10n.tr("health_export.status.requesting")
            try await exporter.requestAuthorization(for: draft)
            let payload = try await exporter.buildPayload(for: draft)
            let data = try payload.jsonData
            guard let json = String(data: data, encoding: .utf8), !json.isEmpty else {
                throw ExportError.invalidPreview
            }
            previewPayload = payload
            previewSummary = previewSummaryText(for: payload)
            previewJSON = json
            statusMessage = L10n.tr("health_export.status.preview_ready")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = message
        }
        isGeneratingPreview = false
    }

    func sendNow() async {
        guard let previewPayload else {
            statusMessage = L10n.tr("health_export.status.generate_first")
            return
        }
        isSending = true
        statusMessage = ""
        do {
            let result = try await HealthKitExporter().send(payload: previewPayload)
            store.markSent(id: draft.id, status: result)
            if let updated = store.configuration(id: draft.id) { draft = updated }
            statusMessage = result
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            store.markSent(id: draft.id, status: message)
            if let updated = store.configuration(id: draft.id) { draft = updated }
            statusMessage = message
        }
        isSending = false
    }

    private func previewSummaryText(for payload: HealthExportPayload) -> String {
        if payload.itemCount == 0 {
            return L10n.tr("health_export.preview_summary_empty")
        }
        return L10n.tr("health_export.preview_summary_count", payload.itemCount)
    }
}
