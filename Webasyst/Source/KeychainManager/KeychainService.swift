import Security
import Foundation

struct WebasystKeychainFailure: Error {
    let status: OSStatus
}

enum WebasystKeychainScope: String, CaseIterable {
    case group, local, past
}

protocol WebasystKeychainAccess {
    func read(_ query: [String: Any]) -> (OSStatus, Data?)
    func add(_ query: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct WebasystSystemKeychain: WebasystKeychainAccess {
    func read(_ query: [String: Any]) -> (OSStatus, Data?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func add(_ query: [String: Any]) -> OSStatus { SecItemAdd(query as CFDictionary, nil) }
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
    func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

/// Keeps the existing v2 and legacy query identities; no persisted-data migration is required.
final class WebasystKeychainStore {
    private let access: WebasystKeychainAccess
    private let accountPrefix: String
    private let accessGroup: String?
    private let lock = NSRecursiveLock()

    init(access: WebasystKeychainAccess = WebasystSystemKeychain(),
         accountPrefix: String = "auth_tokens_v2", accessGroup: String? = "group.com.webasyst.shared") {
        self.access = access
        self.accountPrefix = accountPrefix
        self.accessGroup = accessGroup
    }

    private func synchronized<Value>(_ action: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return action()
    }

    func read(_ key: KeychainEnum, scope: WebasystKeychainScope = .local) -> Result<Data?, WebasystKeychainFailure> {
        synchronized {
            var query = identity(key, scope: scope)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            let (status, data) = access.read(query)
            if status == errSecItemNotFound { return .success(nil) }
            guard status == errSecSuccess else { return .failure(WebasystKeychainFailure(status: status)) }
            guard let data else { return .failure(WebasystKeychainFailure(status: errSecDecode)) }
            return .success(data)
        }
    }

    @discardableResult
    func write(_ key: KeychainEnum, data: Data, scope: WebasystKeychainScope = .local) -> OSStatus {
        synchronized {
            let query = identity(key, scope: scope)
            // Update in place. A failed update must not delete the existing credential.
            let status = access.update(query, attributes: [kSecValueData as String: data])
            guard status == errSecItemNotFound else { return status }
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let added = access.add(item)
            // Another process may have created the item between update and add.
            if added == errSecDuplicateItem {
                return access.update(query, attributes: [kSecValueData as String: data])
            }
            return added
        }
    }

    func savePair(_ pair: WebasystTokenPair) -> OSStatus {
        synchronized {
            // Preserve a rotated refresh token even if saving the access token subsequently fails.
            let refreshStatus = write(.refreshToken, data: pair.refresh)
            guard refreshStatus == errSecSuccess else { return refreshStatus }
            let accessStatus = write(.accessToken, data: pair.access)
            guard accessStatus == errSecSuccess else { return accessStatus }
            _ = write(.refreshToken, data: pair.refresh, scope: .group)
            _ = write(.accessToken, data: pair.access, scope: .group)
            return errSecSuccess
        }
    }

    func delete(_ scopes: [WebasystKeychainScope] = WebasystKeychainScope.allCases) {
        synchronized {
            for scope in scopes {
                for key in [KeychainEnum.accessToken, .refreshToken] {
                    _ = access.delete(identity(key, scope: scope))
                }
            }
        }
    }

    private func identity(_ key: KeychainEnum, scope: WebasystKeychainScope) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword]
        query[kSecAttrAccount as String] = scope == .past ? key.rawValue : "\(accountPrefix)_\(scope.rawValue)"
        if scope != .past { query[kSecAttrService as String] = key.rawValue }
        if scope == .group, let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}

final class KeychainManager {
    private init() {}
    // Persist a local logout even when Security cannot delete a locked item. Keep each
    // credential blocked until that credential is explicitly replaced (watchOS setToken).
    private static let invalidatedKeys = "Webasyst_auth_invalidated_local_keys"
    // Internal seams let native tests use a unique Keychain namespace and real Security APIs.
    static var store = WebasystKeychainStore()

    static func readToken(_ key: KeychainEnum, scope: WebasystKeychainScope = .local) -> Result<String?, WebasystKeychainFailure> {
        if scope == .local, blockedKeys?.contains(key.rawValue) == true { return .success(nil) }
        if scope == .past, blockedKeys != nil { return .success(nil) }
        switch store.read(key, scope: scope) {
        case .success(nil): return .success(nil)
        case .success(let data?):
            guard let token = String(data: data, encoding: .utf8) else {
                return .failure(WebasystKeychainFailure(status: errSecDecode))
            }
            return .success(token)
        case .failure(let error): return .failure(error)
        }
    }

    static func getToken(_ key: KeychainEnum) -> String {
        guard case .success(let token) = readToken(key) else { return "" }
        return token ?? ""
    }

    static func getData(from key: KeychainEnum) -> Data? {
        guard case .success(let token?) = readToken(key) else { return nil }
        return Data(token.utf8)
    }

    static func save(_ key: KeychainEnum, data: Data) -> OSStatus {
        let status = store.write(key, data: data)
        guard status == errSecSuccess else { return status }
        unblock([key])
        _ = store.write(key, data: data, scope: .group)
        if key == .refreshToken, !data.isEmpty { markLoggedIn() }
        NotificationCenter.default.post(name: NSNotification.Name("\(key)Updated"), object: nil)
        return status
    }

    static func savePair(_ pair: WebasystTokenPair) -> OSStatus {
        let status = store.savePair(pair)
        if status == errSecSuccess {
            unblock([.accessToken, .refreshToken])
            markLoggedIn()
        }
        return status
    }

    static func notifyTokensUpdated() {
        for key in [KeychainEnum.accessToken, .refreshToken] {
            NotificationCenter.default.post(name: NSNotification.Name("\(key)Updated"), object: nil)
        }
    }

    static func deleteAll() {
        blockLocalCredentials()
        store.delete()
    }

    static func deleteLocal() {
        blockLocalCredentials()
        store.delete([.local, .past])
    }

    private static var blockedKeys: [String]? { UserDefaults.standard.stringArray(forKey: invalidatedKeys) }

    private static func blockLocalCredentials() {
        UserDefaults.standard.set([KeychainEnum.accessToken.rawValue, KeychainEnum.refreshToken.rawValue], forKey: invalidatedKeys)
    }

    private static func unblock(_ keys: [KeychainEnum]) {
        guard let blocked = blockedKeys else { return }
        // Retain even an empty array: legacy/shared automatic restoration must not undo logout.
        UserDefaults.standard.set(blocked.filter { value in !keys.contains { $0.rawValue == value } }, forKey: invalidatedKeys)
    }

    /// Migrate only readable legacy data. Shared tokens are exchanged on the server before any local write.
    static func prepareRestoration() -> Result<Bool, WebasystKeychainFailure> {
        guard blockedKeys == nil else { return .success(false) }
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.isLoggedIn.rawValue) { return .success(false) }
        switch readToken(.refreshToken) {
        case .failure(let error): return .failure(error)
        case .success(let token) where !(token ?? "").isEmpty: return .success(false)
        default: break
        }
        switch store.read(.refreshToken, scope: .past) {
        case .failure(let error): return .failure(error)
        case .success(let refresh?) where !refresh.isEmpty:
            switch store.read(.accessToken, scope: .past) {
            case .failure(let error): return .failure(error)
            case .success(let access):
                let status: OSStatus
                if let access, !access.isEmpty {
                    status = savePair(WebasystTokenPair(access: access, refresh: refresh))
                } else {
                    // An expired/missing legacy access token can be recovered using its refresh.
                    status = save(.refreshToken, data: refresh)
                }
                guard status == errSecSuccess else { return .failure(WebasystKeychainFailure(status: status)) }
                store.delete([.past])
                notifyTokensUpdated()
                return .success(false)
            }
        default: break
        }
        switch readToken(.accessToken, scope: .group) {
        case .success(let token): return .success(!(token ?? "").isEmpty)
        case .failure(let error) where error.status == errSecMissingEntitlement:
            return .success(false) // Shared Keychain is optional for existing applications.
        case .failure(let error): return .failure(error)
        }
    }

    static func checkRestorationSuccess() -> Bool {
        guard case .success(let restore) = prepareRestoration() else { return false }
        return restore
    }

    private static func markLoggedIn() {
        UserDefaults.standard.setValue(true, forKey: UserDefaultsKeys.isLoggedIn.rawValue)
    }
}
