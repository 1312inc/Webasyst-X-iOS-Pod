import Foundation

public extension Notification.Name {
    /// Sanitized authentication diagnostics. No credentials, bodies or account identifiers are included.
    /// Observe this notification to forward `userInfo` to the application's own logging service.
    static let webasystAuthDiagnostic = Notification.Name("Webasyst_auth_diagnostic")
}

enum WebasystAuthFailureKind: String {
    case configuration, missingCredentials, transport, server, decoding, keychain, rejected, superseded
}

struct WebasystAuthFailure: Error {
    let kind: WebasystAuthFailureKind
    let error: WebasystError
    let generation: UInt64

    static func make(_ kind: WebasystAuthFailureKind, generation: UInt64,
                     status: Int? = nil, code: Int? = nil, domain: String? = nil,
                     oauthError: String? = nil) -> Self {
        let key: String
        switch kind {
        case .configuration: key = "error.missedConfig"
        case .missingCredentials, .rejected: key = "error.invalidRefreshToken"
        case .transport: key = "connectionAlertMessage"
        case .decoding: key = "unableToDecodeResponsedData"
        case .keychain: key = "error.keychainSave"
        case .superseded: key = "error.token"
        case .server: key = "unownedErrorWithStatusCode"
        }
        let message = WebasystApp.getDefaultLocalizedString(withKey: key)
            .replacingOccurrences(of: "%CODE%", with: status.map(String.init) ?? "")
        return Self(kind: kind, error: WebasystError(localizedError: message, statusCode: status,
                    errorValue: oauthError, underlyingErrorDomain: domain, underlyingErrorCode: code),
                    generation: generation)
    }
}

enum WebasystAuthDiagnostics {
    static func record(_ operation: String, outcome: String, host: String? = nil,
                       failure: WebasystAuthFailure? = nil, duration: TimeInterval? = nil) {
        var values: [String: Any] = ["operation": operation, "outcome": outcome]
        // Host comes from SDK configuration, never from an installation URL or response body.
        if let host { values["host"] = host }
        if let duration { values["duration_ms"] = Int(duration * 1000) }
        if let failure {
            values["reason"] = failure.kind.rawValue
            values["http_status"] = failure.error.statusCode
            values["error_domain"] = failure.error.underlyingErrorDomain
            values["error_code"] = failure.error.underlyingErrorCode
        }
        NotificationCenter.default.post(name: .webasystAuthDiagnostic, object: nil, userInfo: values)
    }
}

/// A callback gate for APIs which combine timeout and several asynchronous requests.
final class WebasystCompletion<Value> {
    private let lock = NSLock()
    private var completion: ((Value) -> Void)?

    init(_ completion: @escaping (Value) -> Void) { self.completion = completion }

    var isCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completion == nil
    }

    func call(_ value: Value) {
        lock.lock()
        let action = completion
        completion = nil
        lock.unlock()
        action?(value)
    }
}
