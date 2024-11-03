//
//  KeychainService.swift
//  WebXApp
//
//  Created by Виктор Кобыхно on 1/15/21.
//

import Security
import Foundation

final class KeychainManager {
    
    
    // MARK: Init
    
    private init() {}
    
    //
    
    
    // MARK: Methods
    
    static func checkRestorationSuccess() -> Bool {
        
        // Temporary commented
        
//        let localRefreshTokenData = getKeychainData(from: .refreshToken, type: .local)
//
//        if localRefreshTokenData == nil {
//            if let groupRefreshTokenData = getKeychainData(from: .refreshToken, type: .group) {
//                let status = saveKeychainData(.refreshToken, data: groupRefreshTokenData, type: .local)
//
//                if let groupAccessTokenData = getKeychainData(from: .accessToken, type: .group) {
//                    _ = saveKeychainData(.accessToken, data: groupAccessTokenData, type: .local)
//                }
//
//                return status == noErr
//            } else {
//                return false
//            }
//        } else {
//            return false
//        }
        
        //
        
        return false
    }
    
    static func getToken(_ key: KeychainEnum) -> String {
        guard let data = getData(from: key), let token = String(data: data, encoding: .utf8) else { return "" }
        return token
    }
    
    static func save(_ key: KeychainEnum, data: Data) -> OSStatus {
        let status = saveKeychainData(key, data: data, type: .local)
        
        // Temporary commented
        
//        _ = saveKeychainData(key, data: data, type: .group)
        
        //
        
        return status
    }
    
    static func getData(from key: KeychainEnum) -> Data? {
        
        // Temporary commented
        
//        if let localTokenData = getKeychainData(from: key, type: .local) {
//            return localTokenData
//        } else if let groupTokenData = getKeychainData(from: key, type: .group) {
//            return groupTokenData
//        } else {
//            return nil
//        }
        
        //
        
        return getKeychainData(from: key, type: .local)
    }
    
    static func deleteAll() {
        deleteAllKeychainData()
    }
    
    //
    
}


// MARK: - Private

private
extension KeychainManager {
    
    
    // MARK: Parameters
    
    static private let accessGroup: String = "group.com.webasyst.shared"
    
    //
    
    
    // MARK: Methods
    
    static func saveKeychainData(_ key: KeychainEnum, data: Data, type: KeychainDataType) -> OSStatus {
        let keychainQuery = generateKeychainQuery(key: key, data: data, type: type)
        
        SecItemDelete(keychainQuery as CFDictionary)
        
        let osStatus = SecItemAdd(keychainQuery as CFDictionary, nil)
        
        if osStatus == 0, case .local = type {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "\(key)Updated"), object: nil)
        }
        
        return osStatus
    }
    
    static func getKeychainData(from key: KeychainEnum, type: KeychainDataType) -> Data? {
        let keychainQuery = generateKeychainQuery(key: key, type: type)
        
        var data: AnyObject?
        
        let status = SecItemCopyMatching(keychainQuery as CFDictionary, &data)
        
        if status == noErr {
            return data as? Data
        } else {
            return nil
        }
    }
    
    static func deleteAllKeychainData() {
        let queries: [[String : Any]] = [
            
            // Temporary commented
            
//            generateKeychainQuery(key: .accessToken, type: .group, forDelete: true),
//            generateKeychainQuery(key: .refreshToken, type: .group, forDelete: true),
            
            //
            
            generateKeychainQuery(key: .accessToken, type: .local, forDelete: true),
            generateKeychainQuery(key: .refreshToken, type: .local, forDelete: true)
        ]
        
        for query in queries {
            SecItemDelete(query as CFDictionary)
        }
    }
    
    //
    
    
    // MARK: Support
    
    static func generateKeychainQuery(key: KeychainEnum, data: Data? = nil, type: KeychainDataType, forDelete delete: Bool = false) -> [String : Any] {
        var keychainQuery: [String : Any] =
        [
            kSecClass as String         : kSecClassGenericPassword,
            kSecAttrAccount as String   : key.rawValue
        ]
        
        // Temporary commented
        
//        switch type {
//        case .group:
//            keychainQuery[kSecAttrAccessGroup as String] = accessGroup
//            keychainQuery[kSecAttrService as String] = "group"
//        case .local:
//            keychainQuery[kSecAttrService as String] = "local"
//        }
        
        //
        
        if !delete {
            if let data {
                keychainQuery[kSecValueData as String] = data
            } else {
                keychainQuery[kSecReturnData as String] = true
                keychainQuery[kSecMatchLimit as String] = kSecMatchLimitOne
            }
        }
        
        return keychainQuery
    }
    
    //
    
}


// MARK: - Private Model

private
extension KeychainManager {
    
    enum KeychainDataType {
        case group
        case local
    }
}
