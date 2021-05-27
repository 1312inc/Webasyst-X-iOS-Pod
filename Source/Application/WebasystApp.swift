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
    
    public init() {}
    
    /// Webasyst library configuration method
    /// - Parameters:
    ///   - bundleId: Bundle Id of your application, required for authorization on the server
    ///   - clientId: Client Id of your application
    ///   - host: application server host
    public func configure(clientId: String, host: String, scope: String) {
        if scope.contains("webasyst") {
            WebasystApp.config = WebasystConfig(clientId: clientId, host: host, scope: scope)
        } else {
            WebasystApp.config = WebasystConfig(clientId: clientId, host: host, scope: "\(scope),webasyst")
        }
        
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
    
    /// Webasyst server authorization method
    /// - Parameters:
    ///   - navigationController: UINavigationController to display the OAuth webasyst modal window
    ///   - action: Closure to perform an action after authorization
    @available(*, deprecated, message: "This method is obsolete, use oAuthLogin")
    public func authWebasyst(navigationController: UINavigationController, action: @escaping ((_ result: WebasystServerAnswer) -> ())) {
        let coordinator = AuthCoordinator(navigationController)
        coordinator.start()
        let success: ((_ action: WebasystServerAnswer) -> Void) = { success in
            switch success {
            case .success:
                WebasystUserNetworking().preloadUserData { text, _, status in
                    if status {
                        action(WebasystServerAnswer.success)
                    } else {
                        action(WebasystServerAnswer.error(error: text))
                    }
                }
            case .error(error: let error):
                action(WebasystServerAnswer.error(error: error))
            }
        }
        coordinator.action = success
    }
    
    /// Webasyst server authorization method
    /// - Parameters:
    ///   - navigationController: UINavigationController to display the OAuth webasyst modal window
    ///   - action: Closure to perform an action after authorization
    public func oAuthLogin(navigationController: UINavigationController, action: @escaping ((_ result: WebasystServerAnswer) -> ())) {
        let coordinator = AuthCoordinator(navigationController)
        coordinator.start()
        let success: ((_ action: WebasystServerAnswer) -> Void) = { success in
            switch success {
            case .success:
                WebasystUserNetworking().preloadUserData { text, _, status in
                    if status {
                        action(WebasystServerAnswer.success)
                    } else {
                        action(WebasystServerAnswer.error(error: text))
                    }
                }
            case .error(error: let error):
                action(WebasystServerAnswer.error(error: error))
            }
        }
        coordinator.action = success
    }
    
    /// Method for obtaining authorisation code without a browser
    /// - Parameters:
    ///   - value: Phone number or email
    ///   - type: Value type(.email/.phone)
    ///   - success: Closure performed after the method has been executed
    /// - Returns: Status of code sent to the user by email or text message, see AuthResult documentation for a detailed description of statuses
    public func getAuthCode(_ value: String, type: AuthType, success: @escaping (AuthResult) -> ()) {
        WebasystNetworking().getAuthCode(value, type: type) { result in
            success(result)
        }
    }
    
    /// Sending a confirmation code after calling the getAuthCode method
    /// - Parameters:
    ///   - code: Code received by user by e-mail or text message
    ///   - success: Closure performed after the method has been executed
    /// - Returns: Bool value whether the server has accepted the code, if true then the tokens are saved in the Keychain
    public func sendConfirmCode(_ code: String, success: @escaping (Bool) -> ()) {
        WebasystNetworking().sendConfirmCode(code) { result in
            success(result)
        }
    }
    
    /// User authentication check on Webasyst server
    /// - Parameter completion: The closure performed after the check returns a Bool value of whether the user is authorized or not
    /// - Returns Returns user status in the application (.authorized/.nonAuthorized/.error(message: String))
    public func checkUserAuth(completion: @escaping (UserStatus) -> ()) {
        
        let accessToken = KeychainManager.load(key: "accessToken")
        
        if accessToken != nil {
            WebasystUserNetworking().preloadUserData { text, _, status in
                if status {
                    completion(UserStatus.authorized)
                } else {
                    completion(UserStatus.error(message: text))
                }
            }
        } else {
            completion(UserStatus.nonAuthorized)
        }
    }
    
    /// Getting user install list
    /// - Returns: List of all user installations in UserInstall format (name, clientId, domain, accessToken, url)
    public func getAllUserInstall(_ result: @escaping ([UserInstall]?) -> ()) {
        let installList = WebasystDataModel()?.getInstallList()
        result(installList)
    }
    
    /// Obtaining user installation
    /// - Parameter clientId: clientId setting
    /// - Returns: Installation in User Install format 
    public func getUserInstall(_ clientId: String) -> UserInstall? {
        let installRequest = WebasystDataModel()?.getInstall(with: clientId)
        guard let install = installRequest else {
            return nil
        }
        return install
    }
    
    /// Deletes the installation from the database
    /// - Parameter clientId: clientId install
    public func deleteInstall(_ clientId: String) {
        WebasystDataModel()?.deleteInstall(clientId: clientId)
    }
    
    /// Returns user profile data
    /// - Returns: User profile data in ProfileData format
    public func getProfileData() -> ProfileData? {
        var result: ProfileData?
        WebasystDataModel()?.getProfile(completion: { profile in
            result = profile
        })
        return result
    }
    
    /// Exit a user from the account and delete all records in the database
    /// - Returns: Boolean value of deauthorization success
    public func logOutUser(completion: @escaping (Bool) -> ()) {
        WebasystUserNetworking().singUpUser { result in
            if result {
                let dataModel = WebasystDataModel()
                dataModel?.resetInstallList()
                dataModel?.deleteProfileData()
                KeychainManager.deleteAllKeys()
                completion(true)
            } else {
                completion(false)
            }
        }
        
    }
    
}
