//
//  WebasystApp watchOS.swift
//  Webasyst-watchOS
//
//  Created by Леонид Лукашевич on 20.08.2023.
//

import Foundation

extension WebasystApp {
    
    /// Method of setting the iOS device identifier for the correct operation of the webasyst framework on watchOS
    /// - Parameters:
    /// - deviceID: Id of iOS device identifier
    public func setDeviceID(_ deviceID: String) {
        UserDefaults.standard.set(deviceID, forKey: "deviceID")
    }
    
    /// A method for setting Webasyst tokens
    /// - Parameter tokenType: Type of token (Access Token or Refresh Token)
    /// - Parameter token: Token in string format for saving
    public func setToken(_ tokenType: TokenType, token: String) {
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
}
