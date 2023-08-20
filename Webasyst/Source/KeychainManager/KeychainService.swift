//
//  KeychainService.swift
//  WebXApp
//
//  Created by Виктор Кобыхно on 1/15/21.
//


import Security
import Foundation

enum KeychainEnum: String {
    case accessToken
    case refreshToken
}

class KeychainManager {
        
    /// Saving an entry in the Keychain
    /// - Parameters:
    ///   - key: Key to save the record
    ///   - data: Data for recording
    /// - Returns: Returns data in OSStatus format
    class func save(key: String, data: Data) -> OSStatus {
        
        let query = [
            kSecClass as String       : kSecClassGenericPassword as String,
            kSecAttrAccount as String : key,
            kSecValueData as String   : data
        ] as [String : Any]
        
        SecItemDelete(query as CFDictionary)
        
        let osStatus = SecItemAdd(query as CFDictionary, nil)
        
        if osStatus == 0 {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "\(key)Updated"), object: nil)
        }
        
        return osStatus
    }
    
    static var token: String {
        let data = load(key: KeychainEnum.accessToken.rawValue)
        if let data, let token = String(data: data, encoding: .utf8) {
            return token
        } else {
            return .init()
        }
    }
    
    /// Retrieving data from the Keychain
    /// - Parameter key: Record key
    /// - Returns: Data in Data format
    class func load(key: String) -> Data? {
        let query = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrAccount as String : key,
            kSecReturnData as String  : kCFBooleanTrue!,
            kSecMatchLimit as String  : kSecMatchLimitOne ] as [String : Any]
        
        var dataTypeRef: AnyObject? = nil
        
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == noErr {
            return dataTypeRef as! Data?
        } else {
            return nil
        }
    }
    
    /// Deletes all data from Kechain
    class func deleteAllKeys() {
        let secItemClasses = [kSecClassGenericPassword, kSecClassInternetPassword, kSecClassCertificate, kSecClassKey, kSecClassIdentity]
        for itemClass in secItemClasses {
            let spec: NSDictionary = [kSecClass: itemClass]
            SecItemDelete(spec)
        }
    }
}

