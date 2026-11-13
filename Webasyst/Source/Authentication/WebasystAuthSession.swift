import Foundation

struct WebasystTokenPair {
    let access: Data
    let refresh: Data
}

/// Serializes authentication state on the main queue, also used by the SDK's Core Data contexts.
/// No lock is held while waiting for a context or while invoking application callbacks.
final class WebasystAuthSession {
    static let shared = WebasystAuthSession()
    typealias RefreshResult = Result<Void, WebasystAuthFailure>

    private final class Refresh {
        let id = UUID()
        let generation: UInt64
        var callbacks: [(RefreshResult) -> Void]
        var task: URLSessionDataTask?

        init(generation: UInt64, completion: @escaping (RefreshResult) -> Void) {
            self.generation = generation
            callbacks = [completion]
        }
    }

    private var version: UInt64 = 0
    private var refresh: Refresh?
    private var pendingTokens: (generation: UInt64, pair: WebasystTokenPair)?
    private(set) var installations = WebasystInstallationState()

    static func onMain<Value>(_ action: () -> Value) -> Value {
        if Thread.isMainThread { return action() }
        return DispatchQueue.main.sync(execute: action)
    }

    var generation: UInt64 { Self.onMain { version } }

    /// Capture credentials and their session together before a background caller builds a request.
    var accessCredentials: (generation: UInt64, token: String) {
        Self.onMain {
            let stamp = version
            return (stamp, KeychainManager.getToken(.accessToken))
        }
    }

    func isCurrent(_ generation: UInt64) -> Bool { Self.onMain { version == generation } }

    @discardableResult
    func ifCurrent(_ generation: UInt64, _ action: () -> Void) -> Bool {
        Self.onMain {
            guard version == generation else { return false }
            action()
            return true
        }
    }

    /// A new login supersedes previous requests, but keeps persisted credentials until it succeeds.
    @discardableResult
    func beginAuthorization(preservePending: Bool = true) -> UInt64 {
        Self.onMain {
            version &+= 1
            installations = WebasystInstallationState()
            let current = version
            if preservePending, let pending = pendingTokens { pendingTokens = (current, pending.pair) }
            else { pendingTokens = nil }
            let previous = refresh
            refresh = nil
            previous?.task?.cancel()
            if let previous {
                previous.callbacks.forEach { $0(.failure(.make(.superseded, generation: previous.generation))) }
            }
            if version == current { installations.notifyChanged() }
            return current
        }
    }

    /// Cleanup and token commits share one queue, so a late response cannot cross a logout/new login.
    @discardableResult
    func invalidate(expected: UInt64? = nil, cleanup: () -> Void) -> Bool {
        Self.onMain {
            guard expected == nil || expected == version else { return false }
            version &+= 1
            installations = WebasystInstallationState()
            pendingTokens = nil
            let previous = refresh
            refresh = nil
            previous?.task?.cancel()
            cleanup()
            if let previous {
                previous.callbacks.forEach { $0(.failure(.make(.superseded, generation: previous.generation))) }
            }
            installations.notifyChanged()
            return true
        }
    }

    func refreshAccessToken(_ completion: @escaping (RefreshResult) -> Void) {
        Self.onMain {
            let stamp = version
            if let active = refresh {
                active.callbacks.append(completion)
                return
            }
            // A rotated token already received from the server must be saved before another refresh.
            if let pending = pendingTokens, pending.generation == stamp {
                completion(persist(pending.pair, generation: stamp))
                return
            }
            guard let config = WebasystApp.config else {
                completion(.failure(.make(.configuration, generation: stamp)))
                return
            }
            let token: String
            switch KeychainManager.readToken(.refreshToken) {
            case .success(let value):
                guard let value, !value.isEmpty else {
                    completion(.failure(.make(.missingCredentials, generation: stamp)))
                    return
                }
                token = value
            case .failure(let failure):
                completion(.failure(.make(.keychain, generation: stamp, code: Int(failure.status), domain: NSOSStatusErrorDomain)))
                return
            }
            let networking = WebasystNetworking()
            guard let url = networking.buildWebasystUrl("/id/oauth2/auth/token", parameters: [:]) else {
                completion(.failure(.make(.configuration, generation: stamp)))
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            do {
                try request.setMultipartFormData(["grant_type": "refresh_token", "refresh_token": token,
                    "client_id": config.clientId, "device_id": networking.getDeviceId()], encoding: .utf8)
            } catch {
                completion(.failure(.make(.configuration, generation: stamp)))
                return
            }
            let flight = Refresh(generation: stamp, completion: completion)
            refresh = flight
            flight.task = requestTokens(request, generation: stamp, operation: "refresh") { result in
                guard self.refresh?.id == flight.id else { return }
                let answer: RefreshResult
                switch result {
                case .success(let tokens): answer = self.accept(tokens, fallbackRefresh: token, generation: stamp, replacingSession: false)
                case .failure(let failure): answer = .failure(failure)
                }
                guard self.refresh?.id == flight.id else { return }
                self.refresh = nil
                flight.callbacks.forEach { callback in
                    callback(self.isCurrent(stamp) ? answer : .failure(.make(.superseded, generation: stamp)))
                }
            }
        }
    }

    /// Token response parsing is shared by refresh, OAuth, SMS/QR, Apple ID and cross-app exchange.
    @discardableResult
    func requestTokens(_ request: URLRequest, generation: UInt64, operation: String,
                       completion: @escaping (Result<UserToken, WebasystAuthFailure>) -> Void) -> URLSessionDataTask {
        let started = Date()
        var request = request
        request.timeoutInterval = 60
        let task = WebasystNetworkingManager.session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                let result: Result<UserToken, WebasystAuthFailure>
                let status = (response as? HTTPURLResponse)?.statusCode
                if !self.isCurrent(generation) {
                    result = .failure(.make(.superseded, generation: generation))
                } else if let error = error as NSError? {
                    result = .failure(.make(.transport, generation: generation, status: status,
                        code: error.code, domain: error.domain))
                } else if let status, (200...299).contains(status), let data {
                    do {
                        let value = try JSONDecoder().decode(UserToken.self, from: data)
                        guard !value.access_token.isEmpty, value.token_type.lowercased() == "bearer" else {
                            throw CocoaError(.coderReadCorrupt)
                        }
                        result = .success(value)
                    } catch {
                        result = .failure(.make(.decoding, generation: generation, status: status))
                    }
                } else {
                    let oauth = data.flatMap { try? JSONDecoder().decode(ErrorModel.self, from: $0).error }
                    let rejected = operation == "refresh" && (status == 400 || status == 401) && oauth == "invalid_grant"
                    result = .failure(.make(rejected ? .rejected : .server, generation: generation,
                        status: status, oauthError: oauth))
                }
                let failure: WebasystAuthFailure?
                if case .failure(let value) = result { failure = value } else { failure = nil }
                WebasystAuthDiagnostics.record(operation, outcome: failure == nil ? "received" : "failed",
                    host: request.url?.host, failure: failure, duration: Date().timeIntervalSince(started))
                // Notification observers are application code and may synchronously log out or log in.
                completion(self.isCurrent(generation) ? result : .failure(.make(.superseded, generation: generation)))
            }
        }
        task.resume()
        return task
    }

    func accept(_ tokens: UserToken, fallbackRefresh: String? = nil, generation: UInt64, replacingSession: Bool = true) -> RefreshResult {
        Self.onMain {
            guard isCurrent(generation) else { return .failure(.make(.superseded, generation: generation)) }
            guard let refresh = tokens.refresh_token ?? fallbackRefresh, !refresh.isEmpty else {
                return .failure(.make(.decoding, generation: generation))
            }
            let targetGeneration = replacingSession ? beginAuthorization(preservePending: false) : generation
            return persist(WebasystTokenPair(access: Data("Bearer \(tokens.access_token)".utf8),
                                             refresh: Data(refresh.utf8)), generation: targetGeneration)
        }
    }

    private func persist(_ pair: WebasystTokenPair, generation: UInt64) -> RefreshResult {
        guard isCurrent(generation) else { return .failure(.make(.superseded, generation: generation)) }
        let status = KeychainManager.savePair(pair)
        guard status == 0 else {
            pendingTokens = (generation, pair)
            let failure = WebasystAuthFailure.make(.keychain, generation: generation,
                code: Int(status), domain: NSOSStatusErrorDomain)
            WebasystAuthDiagnostics.record("persist", outcome: "deferred", failure: failure)
            return .failure(failure)
        }
        pendingTokens = nil
        KeychainManager.notifyTokensUpdated()
        guard isCurrent(generation) else { return .failure(.make(.superseded, generation: generation)) }
        return .success(())
    }
}
