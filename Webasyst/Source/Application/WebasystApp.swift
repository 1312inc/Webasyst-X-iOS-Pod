//
//  Webasyst.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 12.05.2021.
//

import UIKit

/**
 Open class for working with Webasyst
 
 Usage example:
 let webasyst =  WebasystApp();
 webasyst.configure(clientId: String, host: String, scope: String);
 let accessToken = webasyst.getToken(_ tokenType: .access);
 print(token);
 */

public class WebasystApp {
    
    internal static var config: WebasystConfig?
    
    let profileInstallService = WebasystDataModel()
    let networking = WebasystNetworking()
    let userNetworking = WebasystUserNetworking()
    
    public init() {}
    
    /// Return url for local storage
    public class func url() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("settings")
    }
    
    /// Returns the NSLocalizedString contained in the Webasyst localisation files
    /// - Parameters:
    ///   - key: Parameter for NSLocalizedString method
    ///   - comment: Parameter for NSLocalizedString method
    /// - Returns: String returned by NSLocalizedString
    public class func getDefaultLocalizedString(withKey key: String, comment: String? = nil) -> String {
        return NSLocalizedString(key, bundle: Bundle(for: self), comment: comment ?? key)
    }
    
    /// A method for getting Webasyst tokens
    /// - Parameter tokenType: Type of token (Access Token or Refresh Token)
    /// - Returns: Requested token in string format
    public func getToken(_ tokenType: TokenType) -> String? {
        let tokenString: String?
        switch tokenType {
        case .access:
            let token = KeychainManager.load(key: "accessToken")
            tokenString = String(decoding: token ?? Data("".utf8), as: UTF8.self)
        case .refresh:
            let token = KeychainManager.load(key: "refreshToken")
            tokenString = String(decoding: token ?? Data("".utf8), as: UTF8.self)
        }
        return tokenString
    }
    
    /// App installation
    /// - Parameters:
    ///   - app:Application name
    ///   - completion: The closure performed after the check returns a Bool value about whether the result was successful or not and a description of the error, if there was one
    public func checkInstallApp(app: String, completion: @escaping (Swift.Result<String?, String>) -> Void) {
        userNetworking.checkAppInstall(app: app, completion: completion)
    }
    
    /// Tries to find a free (not tied to the installation) license from the user whose token is accessed by the mobile application. If there is one, then binds it to the installation. Otherwise, it creates a trial product license tied to the installation.
    /// - Parameters:
    ///   - app: Application name
    ///   - completion: The closure performed after the check returns a Bool value of whether the user is authorized or not
    public func checkLicense(app: String, completion: @escaping (Swift.Result<String?, String>) -> Void) {
        userNetworking.checkInstallLicense(app: app, completion: completion)
    }
    
    /// Tries to find a free (not tied to the installation) license from the user whose token is accessed by the mobile application. If there is one, then binds it to the installation. Otherwise, it creates a trial product license tied to the installation.
    /// - Parameters:
    ///   - type: Type of subscription plan
    ///   - date: Subscription cut-off date
    ///   - completion: The closure performed after the check returns a Bool value of whether the user is authorized or not
    public func extendLicense(type: String, date: String, completion: @escaping (Swift.Result<String?, String>) -> Void) {
        userNetworking.extendLicense(type: type, date: date, completion: completion)
    }
    
    /// Getting user install list
    /// - Parameter completion: List of all user installations in UserInstall format (name, clientId, domain, accessToken, url)
    public func getAllUserInstall(_ result: @escaping ([UserInstall]?) -> ()) {
        let installList = profileInstallService?.getInstallList()
        result(installList)
    }
    
    /// Updating and Getting user install list from server
    /// - Parameter completion: List of all user installations in UserInstallCodable format (name, clientId, domain, accessToken, url)
    public func updateUserInstalls(_ result: @escaping ([UserInstallCodable]?) -> ()) {
        userNetworking.getInstallList { [weak self] updatedInstalls in
            if let installs = updatedInstalls {
                if installs.count == 0 {
                    result(updatedInstalls)
                } else {
                    var clientId: [String] = []
                    for install in installs {
                        clientId.append(install.id)
                    }
                    self?.userNetworking.getAccessTokenApi(clientId: clientId) { (success, accessToken) in
                        if success, let token = accessToken {
                            self?.userNetworking.getAccessTokenInstall(installs, accessCodes: token) { (_, saveSuccess) in
                                result(updatedInstalls)
                            }
                        } else {
                            result(updatedInstalls)
                        }
                    }
                }
            } else {
                result(updatedInstalls)
            }
        }
    }
    
    /// Obtaining user installation
    /// - Parameter clientId: clientId setting
    /// - Returns: Installation in User Install format
    public func getUserInstall(_ clientId: String) -> UserInstall? {
        let installRequest = profileInstallService?.getInstall(with: clientId)
        guard let install = installRequest else {
            return nil
        }
        return install
    }
    
    /// Returns user profile data
    /// - Returns: User profile data in ProfileData format
    public func getProfileData() -> ProfileData? {
        var result: ProfileData?
        profileInstallService?.getProfile(completion: { profile in
            result = profile
        })
        return result
    }
}
