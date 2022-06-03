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
    public func configure() {
        if  let path = Bundle.main.path(forResource: "Webasyst", ofType: "plist"), let xml = FileManager.default.contents(atPath: path), let preferences = try? PropertyListDecoder().decode(Preferences.self, from: xml) {
            if preferences.scope.contains("webasyst") {
                WebasystApp.config = WebasystConfig(clientId: preferences.clientId, host: preferences.host, scope: preferences.scope)
            } else {
                WebasystApp.config = WebasystConfig(clientId: preferences.clientId, host: preferences.host, scope: "\(preferences.scope).webasyst")
            }
        } else {
            print(NSError(domain: "Webasyst error(method: configure): Webasyst configuration error, check if there is a Webasyst.plist file in the root of the project", code: 500, userInfo: nil))
        }
    }
    
    public class func url() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("settings")
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
                action(WebasystServerAnswer.success)
                WebasystUserNetworking().preloadUserData { _, _, _ in }
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
    public func oAuthLogin(navigationController: UINavigationController, action: @escaping ((_ result: UserStatus) -> ())) {
        let coordinator = AuthCoordinator(navigationController)
        coordinator.start()
        let success: ((_ action: WebasystServerAnswer) -> Void) = { success in
            switch success {
            case .success:
                WebasystUserNetworking().preloadUserData { status, _, successPreload in
                    if successPreload {
                        UserDefaults.standard.setValue(false, forKey: "firstLaunch")
                    }
                    action(status)
                }
            case .error(let error):
                action(.error(message: error))
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
            if result {
                WebasystUserNetworking().preloadUserData { _, _, result in
                    UserDefaults.standard.setValue(false, forKey: "firstLaunch")
                    success(result)
                }
            } else {
                success(result)
            }
        }
    }
    
    public func checkInstallApp(completion: @escaping (InstallStatus) -> Void) {
        WebasystUserNetworking().checkAppInstall(completion: completion)
    }
    
    public func checkLicense(completion: @escaping (LicenseStatus) -> Void) {
        WebasystUserNetworking().checkInstallLicense(completion: completion)
    }
    
    /// User authentication check on Webasyst server
    /// - Parameter completion: The closure performed after the check returns a Bool value of whether the user is authorized or not
    public func defaultChecking(completion: @escaping (Bool) -> ()) {
        if let condition = UserDefaults.standard.value(forKey: "firstLaunch") as? Bool {
        completion(condition)
        } else { completion(true) }
        WebasystNetworking().refreshAccessToken { _ in 
        WebasystUserNetworking().preloadUserData { _,_,_ in }
        }
    }
    
    /// User authentication check on Webasyst server
    /// - Parameter completion: updating the user token, and checking authorization
    /// - Returns Returns user status in the application (.authorized/.nonAuthorized/.authorizedButNoneInstalls/.networkError(message: String)/.authorizedButProfileIsEmpty/.error(message: String))
    public func checkUserAuth(completion: @escaping (UserStatus) -> ()) {
        
        WebasystNetworking().refreshAccessToken { result in
            if result {
                WebasystUserNetworking().preloadUserData { status, _, _ in
                   completion(status)
                }
            } else {
                completion(UserStatus.error(message: "not success refresh token"))
            }
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
    
    /// Update current user image
    /// - Parameter image: Image to update
    /// - Parameter success: Closure performed after executing the method
    /// - Returns: Result value which can be successfully or errorable
    public func updateUserImage(_ image: UIImage, success: @escaping (Result) -> Void) {
        WebasystUserNetworking().updateUserAvatar(image) { result in
            success(result)
        }
    }
    
    /// Delete current user image
    /// - Parameter success: Closure performed after executing the method
    /// - Returns: Result value which can be successfully or errorable
    public func deleteUserImage(success: @escaping (Result) -> Void) {
        WebasystUserNetworking().deleteUserAvatar { result in
            success(result)
        }
    }
    
    /// Change the data of the current user
    /// - Parameter profile: pass the current data model with user information
    /// - Parameter success: Closure performed after executing the method
    /// - Returns: Result value which can be successfully or errorable
    public func changeCurrentUserData(profile: ProfileData, success: @escaping (Swift.Result<ProfileData,Error>) -> Void) {
        WebasystUserNetworking().changeUserData(profile) { result in
            success(result)
        }
    }
    
    /// Creating a new Webasyst account
    /// - Parameter success: Closure performed after executing the method
    /// - Returns: Boolean value if the account was created and url install
    public func createWebasystAccount(success: @escaping (Bool, String?)->()) {
        WebasystUserNetworking().createWebasystAccount { result, urlInstall in
            success(result, urlInstall)
        }
    }
    
    /// Exit a user from the account and delete all records in the database
    /// - Returns: Boolean value of deauthorization success
    public func logOutUser(completion: @escaping (Bool) -> ()) {
        let webasystNetworking = WebasystUserNetworking()
        webasystNetworking.singUpUser { _ in }
        let dataModel = WebasystDataModel()
        dataModel?.resetInstallList()
        dataModel?.deleteProfileData()
        KeychainManager.deleteAllKeys()
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        UserDefaults.standard.set(true, forKey: "firstLaunch")
        completion(true)
    }
    
}
