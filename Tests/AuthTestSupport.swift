import XCTest
import Security
@testable import Webasyst

final class AuthURLProtocol: URLProtocol {
    static var handler: ((AuthURLProtocol) -> Void)?
    static var requests: [URLRequest] = []
    private let lock = NSLock()
    private var stopped = false
    private var stoppedLoading: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        DispatchQueue.main.async {
            guard !self.stoppedLoading else { return }
            Self.requests.append(self.request)
            guard let handler = Self.handler else {
                XCTFail("Unexpected network request; live network is disabled")
                self.fail(URLError(.unsupportedURL))
                return
            }
            handler(self)
        }
    }

    override func stopLoading() { lock.lock(); stopped = true; lock.unlock() }

    func reply(status: Int = 200, body: Data = Data()) {
        guard !stoppedLoading else { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    func fail(_ error: Error) { client?.urlProtocol(self, didFailWithError: error) }
}

/// Fault injection delegates every non-failing operation to the real simulator Keychain.
final class FaultingKeychain: WebasystKeychainAccess {
    let system = WebasystSystemKeychain()
    var readFailure: OSStatus?
    var deleteFailure: OSStatus?
    var afterAccessRead: (() -> Void)?
    var writeFailureKey: KeychainEnum?
    var writeFailure: OSStatus = errSecInteractionNotAllowed

    func read(_ query: [String: Any]) -> (OSStatus, Data?) {
        if let readFailure, (query[kSecAttrAccount as String] as? String)?.hasSuffix("_local") == true {
            return (readFailure, nil)
        }
        let result = system.read(query)
        if (query[kSecAttrAccount as String] as? String)?.hasSuffix("_local") == true,
           query[kSecAttrService as String] as? String == KeychainEnum.accessToken.rawValue {
            let callback = afterAccessRead
            afterAccessRead = nil
            callback?()
        }
        return result
    }
    private func fails(_ query: [String: Any]) -> Bool {
        (query[kSecAttrAccount as String] as? String)?.hasSuffix("_local") == true &&
        (query[kSecAttrService as String] as? String) == writeFailureKey?.rawValue
    }
    func add(_ query: [String: Any]) -> OSStatus { fails(query) ? writeFailure : system.add(query) }
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        fails(query) ? writeFailure : system.update(query, attributes: attributes)
    }
    func delete(_ query: [String: Any]) -> OSStatus { deleteFailure ?? system.delete(query) }
}

class AuthTestCase: XCTestCase {
    var keychain: FaultingKeychain!
    var session: URLSession!
    let accountPrefix = "auth_tokens_v2"
    var observers: [NSObjectProtocol] = []

    override func setUp() {
        super.setUp()
        WebasystAuthSession.onMain {
            WebasystAuthSession.shared.invalidate {}
            keychain = FaultingKeychain()
            // The test host has its own private Keychain on a newly created simulator.
            KeychainManager.store = WebasystKeychainStore(access: keychain, accountPrefix: accountPrefix, accessGroup: nil)
            KeychainManager.deleteAll()
            if let bundle = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: bundle) }
            WebasystApp.setConfiguration(WebasystConfig(clientId: "test-client", host: "auth.example.invalid", scope: "shop.webasyst"))
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AuthURLProtocol.self]
            session = URLSession(configuration: configuration)
            WebasystNetworkingManager.session = session
            AuthURLProtocol.requests = []
            AuthURLProtocol.handler = nil
            WebasystDBConfig.dbFolder = "WebasystAuthRegression"
            WebasystApp().profileInstallService?.resetInstallList()
            WebasystApp().profileInstallService?.deleteProfileData()
        }
    }

    override func tearDown() {
        WebasystAuthSession.onMain {
            WebasystAuthSession.shared.invalidate {}
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            keychain.writeFailureKey = nil
            keychain.readFailure = nil
            keychain.deleteFailure = nil
            KeychainManager.deleteAll()
            AuthURLProtocol.handler = nil
            session.invalidateAndCancel()
            WebasystNetworkingManager.session = .shared
        }
        super.tearDown()
    }

    func observe(_ name: Notification.Name, _ action: @escaping (Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil, using: action))
    }

    func seed() {
        XCTAssertEqual(KeychainManager.savePair(pair("old")), errSecSuccess)
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.firstLaunch.rawValue)
    }

    func pair(_ suffix: String) -> WebasystTokenPair {
        WebasystTokenPair(access: Data("Bearer test-access-\(suffix)".utf8), refresh: Data("test-refresh-\(suffix)".utf8))
    }

    func tokenBody(_ suffix: String = "new", refresh: Bool = true) -> Data {
        var json: [String: Any] = ["access_token": "test-access-\(suffix)", "token_type": "bearer", "expires_in": 3600]
        if refresh { json["refresh_token"] = "test-refresh-\(suffix)" }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    func rawQuery(_ key: KeychainEnum, scope: String = "local") -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrAccount as String: scope == "past" ? key.rawValue : "\(accountPrefix)_\(scope)",
         kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            .merging(scope == "past" ? [:] : [kSecAttrService as String: key.rawValue]) { _, rhs in rhs }
    }

    func rawToken(_ key: KeychainEnum, scope: String = "local") -> String? {
        let (status, data) = keychain.system.read(rawQuery(key, scope: scope))
        XCTAssertTrue(status == errSecSuccess || status == errSecItemNotFound)
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }

    func refresh(status: Int = 200, body: Data? = nil, error: Error? = nil, expected: Bool) {
        let done = expectation(description: "refresh completes once")
        done.assertForOverFulfill = true
        AuthURLProtocol.handler = { stub in
            if let error { stub.fail(error) } else { stub.reply(status: status, body: body ?? self.tokenBody()) }
        }
        // A temporary facade must live until its callback has been delivered.
        WebasystApp().refreshAccessToken { success in
            XCTAssertEqual(success, expected)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }
}
