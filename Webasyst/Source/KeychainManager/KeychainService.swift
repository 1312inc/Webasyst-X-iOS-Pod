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
    
    static func getToken(_ key: KeychainEnum) -> String {
        guard let data = getData(from: key), let token = String(data: data, encoding: .utf8) else { return "" }
        
        return token
    }
    
    static func save(_ key: KeychainEnum, data: Data) -> OSStatus {
        let status = saveKeychainData(key, data: data, type: .default)
        _ = saveKeychainData(key, data: data, type: .group)
        
        return status
    }
    
    static func getData(from key: KeychainEnum) -> Data? {
        if let localTokenData = getKeychainData(from: key, type: .default) {
            return localTokenData
        } else {
            let groupTokenData = getKeychainData(from: key, type: .group)
            
            return groupTokenData
        }
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
        
        if osStatus == 0, case .default = type {
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
            generateKeychainQuery(key: .accessToken, type: .default),
            generateKeychainQuery(key: .refreshToken, type: .default),
            generateKeychainQuery(key: .accessToken, type: .group),
            generateKeychainQuery(key: .refreshToken, type: .group)
        ]
        
        for query in queries {
            SecItemDelete(query as CFDictionary)
        }
    }
    
    //
    
    
    // MARK: Support
    
    static func generateKeychainQuery(key: KeychainEnum, data: Data? = nil, type: KeychainDataType) -> [String : Any] {
        var keychainQuery: [String : Any] =
        [
            kSecClass as String         : kSecClassGenericPassword,
            kSecAttrAccount as String   : key.rawValue
        ]
        
        switch type {
        case .default:
            break
        case .group:
            keychainQuery[kSecAttrAccessGroup as String] = accessGroup
        }
        
        if let data {
            keychainQuery[kSecValueData as String] = data
        } else {
            keychainQuery[kSecReturnData as String] = true
            keychainQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        
        return keychainQuery
    }
    
    //
    
}


// MARK: - Private Model

private
extension KeychainManager {
    
    enum KeychainDataType {
        case `default`
        case group
    }
}
