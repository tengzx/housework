import AppIntents
import Foundation
import UIKit

private enum IntentStrings {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let language = UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? AppLanguage.system.rawValue
        let template = AppIntentLocalizer.text(key, languageCode: language)
        guard !arguments.isEmpty else { return template }
        let locale = language == AppLanguage.en.rawValue ? Locale(identifier: "en") : Locale(identifier: "zh-Hans")
        return String(format: template, locale: locale, arguments: arguments)
    }
}

private enum AppIntentLocalizer {
    private static let tableDirectory = "Resources/I18n"
    private static let fallbackLanguage = "zh-Hans"
    private static let lock = NSLock()
    private static var cache: [String: [String: String]] = [:]

    static func text(_ key: String, languageCode: String) -> String {
        if languageCode == AppLanguage.system.rawValue {
            for candidate in Locale.preferredLanguages {
                let code = candidate.hasPrefix("en") ? "en" : "zh-Hans"
                if let value = dictionary(for: code)?[key] {
                    return value
                }
            }
        } else if let value = dictionary(for: languageCode)?[key] {
            return value
        }
        return dictionary(for: fallbackLanguage)?[key] ?? key
    }

    private static func dictionary(for languageCode: String) -> [String: String]? {
        lock.lock()
        if let cached = cache[languageCode] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let url = Bundle.main.url(forResource: languageCode, withExtension: "json", subdirectory: tableDirectory),
              let data = try? Data(contentsOf: url),
              let dictionary = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }

        lock.lock()
        cache[languageCode] = dictionary
        lock.unlock()
        return dictionary
    }
}

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
        let configs = await MainActor.run { ConfigurationStore.shared.configurations }
        return configs
            .filter { identifiers.contains($0.id) }
            .map { ExportConfigurationEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [ExportConfigurationEntity] {
        let configs = await MainActor.run { ConfigurationStore.shared.configurations }
        return configs.map { ExportConfigurationEntity(id: $0.id, name: $0.name) }
    }

    func entities(matching string: String) async throws -> [ExportConfigurationEntity] {
        let configs = await MainActor.run { ConfigurationStore.shared.configurations }
        return configs
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
        let savedConfigurations = await MainActor.run { ConfigurationStore.shared.configurations }
        let exportConfiguration: ExportConfiguration?
        if let configuration {
            exportConfiguration = savedConfigurations.first(where: { $0.id == configuration.id })
        } else {
            exportConfiguration = savedConfigurations.first
        }

        guard let exportConfiguration else {
            return .result(dialog: IntentDialog(stringLiteral: IntentStrings.text("intent.send_health_data.dialog.missing_config")))
        }

        do {
            let result = try await HealthKitExporter().send(configuration: exportConfiguration, shouldRequestAuthorization: false)
            await ConfigurationStore.shared.markSent(id: exportConfiguration.id, status: result)
            return .result(dialog: IntentDialog(stringLiteral: "\(exportConfiguration.name): \(result)"))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await ConfigurationStore.shared.markSent(id: exportConfiguration.id, status: message)
            return .result(dialog: IntentDialog(stringLiteral: "\(exportConfiguration.name): \(message)"))
        }
    }
}

struct StartAppSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "开始 App 计时"
    static var description = IntentDescription("向服务器记录 App 开始使用，自动填充设备信息和时间。")
    static var openAppWhenRun = false

    @Parameter(title: "App 名称", description: "正在前台运行的 App 名称，如「微信」。")
    var appName: String

    @Parameter(title: "Bundle ID", description: "可选，如 com.tencent.xin。")
    var bundleId: String?

    @Parameter(title: "备注")
    var note: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmedApp = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedApp.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: IntentStrings.text("intent.start_app_session.dialog.empty_app_name")))
        }
        do {
            try await AppSessionAPI.start(appName: trimmedApp, bundleId: bundleId, note: note)
            return .result(dialog: IntentDialog(stringLiteral: IntentStrings.text("intent.start_app_session.dialog.success", trimmedApp)))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .result(dialog: IntentDialog(stringLiteral: IntentStrings.text("intent.start_app_session.dialog.failure", message)))
        }
    }
}

struct EndAppSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "结束 App 计时"
    static var description = IntentDescription("向服务器记录 App 停止使用，自动填充设备信息和时间。")
    static var openAppWhenRun = false

    @Parameter(title: "备注")
    var note: String?

    @Parameter(title: "结束原因", description: "可选，如 stopped、home、switch。默认 stopped。")
    var endReason: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try await AppSessionAPI.end(note: note, endReason: endReason)
            return .result(dialog: IntentDialog(stringLiteral: IntentStrings.text("intent.end_app_session.dialog.success")))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .result(dialog: IntentDialog(stringLiteral: IntentStrings.text("intent.end_app_session.dialog.failure", message)))
        }
    }
}

// MARK: - App Session API

enum AppSessionAPI {
    private static let startURL = AppEnvironment.apiURL("mobile/app-sessions/start")
    private static let endURL = AppEnvironment.apiURL("mobile/app-sessions/end")
    private static let deviceId = "iphone"

    static func start(appName: String, bundleId: String? = nil, note: String? = nil) async throws {
        let isoNow = ISO8601DateFormatter.appSessionFormatter.string(from: Date())
        let body = StartAppSessionRequest(
            userId: 1,
            deviceId: deviceId,
            deviceName: UIDevice.current.name,
            appName: appName,
            bundleId: bundleId.flatMap { $0.isEmpty ? nil : $0 },
            startedAt: isoNow,
            lastEventAt: isoNow,
            source: "iphone-automation",
            note: note.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        )
        let response = try await post(url: startURL, body: body)
        // If the backend detected that this phone use interrupted a running focus
        // task, it returns a reminder for us to surface as a local notification.
        if let reminder = try? JSONDecoder().decode(StartAppSessionResponse.self, from: response.data).focusReminder,
           reminder.isActionable {
            await FocusReminderNotifier.present(reminder)
        }
        // Phone distraction should be actionable when the user opens the app,
        // not after they eventually leave it. At this point the new session is
        // persisted, and the comparison also contains all usage completed so far.
        await IdealDayStore.shared.loadTodayComparison(forceReminder: true)
    }

    static func end(note: String? = nil, endReason: String? = nil) async throws {
        let isoNow = ISO8601DateFormatter.appSessionFormatter.string(from: Date())
        let trimReason = endReason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = EndAppSessionRequest(
            userId: 1,
            deviceId: deviceId,
            endedAt: isoNow,
            lastEventAt: isoNow,
            endReason: (trimReason?.isEmpty == false) ? trimReason : "stopped",
            note: note.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 },
            source: "iphone-automation"
        )
        _ = try await post(url: endURL, body: body)
    }

    @discardableResult
    private static func post<T: Encodable>(url: URL, body: T) async throws -> HTTPClientResponse {
        do {
            return try await HTTPClient.shared.data(url: url, method: .post, body: body)
        } catch let error as HTTPClientError {
            if case let .httpFailure(statusCode, data) = error {
                let message = (try? JSONDecoder().decode(AppSessionErrorResponse.self, from: data))?.error ?? IntentStrings.text("intent.app_session.request_failed")
                throw AppSessionAPIError(statusCode: statusCode, message: message)
            }
            throw error
        }
    }
}

private struct StartAppSessionResponse: Decodable {
    var focusReminder: FocusReminderPayload?
}

private struct StartAppSessionRequest: Encodable {
    var userId: Int
    var deviceId: String
    var deviceName: String?
    var appName: String
    var bundleId: String?
    var startedAt: String?
    var lastEventAt: String?
    var source: String?
    var note: String?
}

private struct EndAppSessionRequest: Encodable {
    var userId: Int
    var deviceId: String
    var endedAt: String?
    var lastEventAt: String?
    var endReason: String?
    var note: String?
    var source: String?
}

private struct AppSessionErrorResponse: Decodable {
    var success: Bool?
    var error: String
}

private struct AppSessionAPIError: LocalizedError {
    var statusCode: Int
    var message: String
    var errorDescription: String? { "\(message) (\(statusCode))" }
}

private extension ISO8601DateFormatter {
    static let appSessionFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Shortcuts Provider

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
        AppShortcut(
            intent: StartAppSessionIntent(),
            phrases: [
                "开始 App 计时 \(.applicationName)",
                "记录 App 开始 \(.applicationName)"
            ],
            shortTitle: "开始 App 计时",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: EndAppSessionIntent(),
            phrases: [
                "结束 App 计时 \(.applicationName)",
                "记录 App 结束 \(.applicationName)"
            ],
            shortTitle: "结束 App 计时",
            systemImageName: "stop.circle.fill"
        )
    }
}
