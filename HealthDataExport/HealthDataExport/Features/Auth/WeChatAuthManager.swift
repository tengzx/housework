import Foundation
#if canImport(WechatOpenSDK)
import WechatOpenSDK
#endif

enum WeChatAuthError: LocalizedError {
    case notConfigured
    case notInstalled
    case cancelled
    case failed

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L10n.tr("auth.wechat_not_configured")
        case .notInstalled: return L10n.tr("auth.wechat_not_installed")
        case .cancelled: return L10n.tr("auth.wechat_cancelled")
        case .failed: return L10n.tr("auth.wechat_failed")
        }
    }
}

/// Wraps the WeChat OpenSDK: registers the app, launches the OAuth authorization
/// flow and turns its delegate callback into an async `code` the backend can redeem.
/// Compiles to a disabled stub when the WechatOpenSDK package is not linked yet.
@MainActor
final class WeChatAuthManager: NSObject {
    static let shared = WeChatAuthManager()

    /// Master switch for the WeChat login entry point. Flip to true once the app
    /// is registered on the WeChat Open Platform and WECHAT_APP_ID is filled in.
    static let featureEnabled = false

    static var appID: String {
        infoString("WECHAT_APP_ID")
    }

    static var universalLink: String {
        infoString("WECHAT_UNIVERSAL_LINK")
    }

    private static func infoString(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pendingContinuation: CheckedContinuation<String, Error>?
    private var pendingState: String?

    private func resume(with result: Result<String, Error>) {
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        pendingState = nil
        continuation.resume(with: result)
    }

#if canImport(WechatOpenSDK)
    /// True when the feature is enabled, the SDK is linked and an AppID is configured
    /// (WECHAT_APP_ID build setting).
    static var isAvailable: Bool { featureEnabled && !appID.isEmpty }

    @discardableResult
    func registerIfNeeded() -> Bool {
        guard Self.isAvailable else { return false }
        return WXApi.registerApp(Self.appID, universalLink: Self.universalLink)
    }

    /// Opens WeChat for authorization and returns the one-time authorization code.
    func authorize() async throws -> String {
        guard Self.isAvailable else { throw WeChatAuthError.notConfigured }
        guard WXApi.isWXAppInstalled() else { throw WeChatAuthError.notInstalled }
        resume(with: .failure(WeChatAuthError.cancelled)) // drop any stale in-flight attempt

        let state = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation
            pendingState = state
            let request = SendAuthReq()
            request.scope = "snsapi_userinfo"
            request.state = state
            WXApi.send(request) { sent in
                if !sent {
                    Task { @MainActor in
                        WeChatAuthManager.shared.resume(with: .failure(WeChatAuthError.failed))
                    }
                }
            }
        }
    }

    func handleOpenURL(_ url: URL) {
        WXApi.handleOpen(url, delegate: self)
    }

    func handleUniversalLink(_ userActivity: NSUserActivity) {
        WXApi.handleOpenUniversalLink(userActivity, delegate: self)
    }
#else
    static var isAvailable: Bool { false }

    @discardableResult
    func registerIfNeeded() -> Bool { false }

    func authorize() async throws -> String { throw WeChatAuthError.notConfigured }

    func handleOpenURL(_ url: URL) {}

    func handleUniversalLink(_ userActivity: NSUserActivity) {}
#endif
}

#if canImport(WechatOpenSDK)
// The SDK invokes its delegate on the main thread, matching this class's MainActor isolation.
extension WeChatAuthManager: @preconcurrency WXApiDelegate {
    func onReq(_ req: BaseReq) {}

    func onResp(_ resp: BaseResp) {
        guard let authResp = resp as? SendAuthResp else { return }
        guard pendingState == nil || authResp.state == pendingState else {
            resume(with: .failure(WeChatAuthError.failed))
            return
        }
        switch Int(authResp.errCode) {
        case Int(WXSuccess.rawValue):
            if let code = authResp.code, !code.isEmpty {
                resume(with: .success(code))
            } else {
                resume(with: .failure(WeChatAuthError.failed))
            }
        case Int(WXErrCodeUserCancel.rawValue), Int(WXErrCodeAuthDeny.rawValue):
            resume(with: .failure(WeChatAuthError.cancelled))
        default:
            resume(with: .failure(WeChatAuthError.failed))
        }
    }
}
#endif
