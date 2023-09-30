//
//  WebasystApp watchOS.swift
//  Webasyst-watchOS
//
//  Created by Леонид Лукашевич on 20.08.2023.
//

import Foundation

public
extension WebasystApp {
    
    /// Method of setting the iOS device identifier for the correct operation of the webasyst framework on watchOS
    /// - Parameter deviceID: Id of iOS device identifier.
    func setDeviceID(_ deviceID: String) {
        UserDefaults.standard.set(deviceID, forKey: "deviceID")
    }
    
    /// A method for setting Webasyst tokens
    /// - Parameters:
    ///    - tokenType: Type of token.
    ///    - token: Token in string format for saving.
    func setToken(_ tokenType: TokenType, token: String) {
        switch tokenType {
        case .access:
            let tokenData = Data(token.utf8)
            let _ = KeychainManager.save(key: "accessToken", data: tokenData)
            UserDefaults.standard.set(token, forKey: "accessToken")
        case .refresh:
            let tokenData = Data(token.utf8)
            let _ = KeychainManager.save(key: "refreshToken", data: tokenData)
        }
    }
    
    /// Delete all records in the database
    /// - Parameter completion: Boolean value of deauthorization success.
    func logOutUser(completion: (Bool) -> ()) {
        profileInstallService?.resetInstallList()
        profileInstallService?.deleteProfileData()
        KeychainManager.deleteAllKeys()
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        UserDefaults.standard.set(true, forKey: "firstLaunch")
        completion(true)
    }
}
