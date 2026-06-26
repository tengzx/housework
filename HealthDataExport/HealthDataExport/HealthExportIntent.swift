import AppIntents
import Foundation

struct ExportConfigurationEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "健康数据接口")
    static var defaultQuery = ExportConfigurationEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ExportConfigurationEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ExportConfigurationEntity] {
        ConfigurationPersistence.load()
            .filter { identifiers.contains($0.id) }
            .map { ExportConfigurationEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [ExportConfigurationEntity] {
        ConfigurationPersistence.load()
            .map { ExportConfigurationEntity(id: $0.id, name: $0.name) }
    }

    func entities(matching string: String) async throws -> [ExportConfigurationEntity] {
        ConfigurationPersistence.load()
            .filter { string.isEmpty || $0.name.localizedCaseInsensitiveContains(string) }
            .map { ExportConfigurationEntity(id: $0.id, name: $0.name) }
    }
}

struct SendHealthDataIntent: AppIntent {
    static var title: LocalizedStringResource = "发送健康数据"
    static var description = IntentDescription("读取选中 Apple Health 指标并发送到已配置接口。")
    static var openAppWhenRun = false

    @Parameter(title: "接口配置", description: "不选择时自动使用 App 中保存的第一个接口配置。")
    var configuration: ExportConfigurationEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let savedConfigurations = ConfigurationPersistence.load()
        let exportConfiguration: ExportConfiguration?
        if let configuration {
            exportConfiguration = savedConfigurations.first(where: { $0.id == configuration.id })
        } else {
            exportConfiguration = savedConfigurations.first
        }

        guard let exportConfiguration else {
            return .result(dialog: "没有找到接口配置，请先打开 Health Export App 添加配置")
        }

        do {
            let result = try await HealthKitExporter().send(configuration: exportConfiguration, shouldRequestAuthorization: false)
            ConfigurationPersistence.markSent(id: exportConfiguration.id, status: result)
            return .result(dialog: "\(exportConfiguration.name)：\(result)")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            ConfigurationPersistence.markSent(id: exportConfiguration.id, status: message)
            return .result(dialog: "\(exportConfiguration.name)：\(message)")
        }
    }
}

struct HealthExportShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendHealthDataIntent(),
            phrases: [
                "发送健康数据到 \(.applicationName)",
                "同步健康数据到 \(.applicationName)"
            ],
            shortTitle: "发送健康数据",
            systemImageName: "heart.text.square.fill"
        )
    }
}
