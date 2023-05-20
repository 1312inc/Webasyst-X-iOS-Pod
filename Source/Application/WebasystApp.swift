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
    
    private let profileInstallService = WebasystDataModel()
    private let userNetworking = WebasystUserNetworking()
    private let networking = WebasystNetworking()
    private var authCoordinator: AuthCoordinator?
    
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
    
    /// Return url for local storage
    public class func url() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("settings")
    }
    
    public class func getDefaultLocalizedString(withKey key: String, comment: String? = nil) -> String {
        return NSLocalizedString(key, bundle: Bundle(for: self), comment: comment ?? key)
    }
    
    public class func requestFullScreenConfetti(for viewController: UIViewController) {
        ConfettiAnimationView.requestFullScreenAnimation(for: viewController)
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
        let success: ((_ action: WebasystServerAnswer) -> Void) = { [weak self] success in
            switch success {
            case .success:
                action(WebasystServerAnswer.success)
                self?.userNetworking.preloadUserData { _, _, _ in }
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
    public func oAuthLogin(with merge: Bool = false, with code: String = "", navigationController: UINavigationController, action: @escaping ((_ result: UserStatus) -> ())) {
        authCoordinator = AuthCoordinator(navigationController)
        guard let coordinator = authCoordinator else { return }
        coordinator.start(with: code)
        let success: ((_ action: WebasystServerAnswer) -> Void) = { [weak self] success in
            switch success {
            case .success:
                UserDefaults.standard.setValue("", forKey: "selectDomainUser")
                self?.userNetworking.preloadUserData { status, _, successPreload in
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
    
    /// Authorization in Webasyst using Apple ID
    /// - Parameters:
    ///    - authData: Authorization data sent by the Apple ID authorization controller
    ///    - result: Closure with result of authorization
    public func oAuthAppleID(authData: AuthAppleIDData, result: @escaping (_ result: AuthAppleIDResult) -> ()) {
        networking.oAuthAppleID(authData: authData) { [weak self] status in
            switch status {
            case .success(let type):
                switch type {
                case .succeess:
                    self?.userNetworking.preloadUserData { status, _, successPreload in
                        if successPreload {
                            UserDefaults.standard.setValue(false, forKey: "firstLaunch")
                        }
                        result(.completed(status))
                    }
                case .needEmailConfirmation(accessToken: let accessToken):
                    let confirmHandler: (AuthAppleIDResult.EmailConfirmation) -> () = { [weak self] confirmation in
                        guard let self = self else { return }
                        switch confirmation.result {
                        case .code(let code):
                            userNetworking.sendAppleIDEmailConfirmationCode(code, accessToken: accessToken, success: { [weak self] success, errorDescription in
                                if success {
                                    self?.userNetworking.preloadUserData { status, _, successPreload in
                                        if successPreload {
                                            UserDefaults.standard.setValue(false, forKey: "firstLaunch")
                                        }
                                        confirmation.successHandler(true, nil)
                                    }
                                } else {
                                    confirmation.successHandler(false, errorDescription)
                                }
                            })
                        case .logout:
                            logOutUser { success in
                                confirmation.successHandler(success, nil)
                            }
                        }
                    }
                    result(.needEmailConfirmation(authData.userEmail, confirmHandler))
                }
            case .error(let description):
                result(.completed(.error(message: description)))
            }
        }
    }
    
    /// Merge result check
    /// - Parameter completion: The closure performed after the check returns a Bool value of the result was successful or not and error description if she is
    public func mergeResultCheck(completion: @escaping (Swift.Result<Bool, String>) -> Void) {
        userNetworking.mergeResultCheck(completion: completion)
    }
    
    /// Method for obtaining authorisation code without a browser
    /// - Parameters:
    ///   - value: Phone number or email
    ///   - type: Value type(.email/.phone)
    ///   - success: Closure performed after the method has been executed
    /// - Returns: Status of code sent to the user by email or text message, see AuthResult documentation for a detailed description of statuses
    public func getAuthCode(_ value: String, type: AuthType, success: @escaping (AuthResult) -> ()) {
        networking.getAuthCode(value, type: type) { result in
            success(result)
        }
    }
    
    /// Sending a confirmation code after calling the getAuthCode method or after reading qr-code
    /// - Parameters:
    ///   - type: Type of confirmation code
    ///   - code: Code received by user by e-mail or text message or qr content
    ///   - success: Closure performed after the method has been executed
    /// - Returns: Bool value whether the server has accepted the code, if true then the tokens are saved in the Keychain
    public func sendConfirmCode(for type: AuthCodeType = .phone, _ code: String, success: @escaping (Bool) -> ()) {
        networking.sendConfirmCode(for: type, code) { [weak self] result in
            if result {
                self?.userNetworking.preloadUserData { _, _, result in
                    UserDefaults.standard.setValue(false, forKey: "firstLaunch")
                    success(result)
                }
            } else {
                success(result)
            }
        }
    }
    
    /// App installation
    /// - Parameter completion: The closure performed after the check returns a Bool value of the result was successful or not and error description if she is
    public func checkInstallApp(app: String, completion: @escaping (Swift.Result<String?, String>) -> Void) {
        userNetworking.checkAppInstall(app: app, completion: completion)
    }
    
    /// Tries to find a free (not tied to the installation) license from the user whose token is accessed by the mobile application. If there is one, then binds it to the installation. Otherwise, it creates a trial product license tied to the installation.
    /// - Parameter completion: The closure performed after the check returns a Bool value of whether the user is authorized or not
    public func checkLicense(app: String, completion: @escaping (Swift.Result<String?, String>) -> Void) {
        userNetworking.checkInstallLicense(app: app, completion: completion)
    }
    
    /// Tries to find a free (not tied to the installation) license from the user whose token is accessed by the mobile application. If there is one, then binds it to the installation. Otherwise, it creates a trial product license tied to the installation.
    /// - Parameter completion: The closure performed after the check returns a Bool value of whether the user is authorized or not
    public func extendLicense(type: String, date: String, completion: @escaping (Swift.Result<String?, String>) -> Void) {
        userNetworking.extendLicense(type: type, date: date, completion: completion)
    }
    
    /// User authentication check on Webasyst server
    /// - Parameter completion: The closure performed after the check returns a Bool value of whether the user is authorized or not
    public func defaultChecking(completion: @escaping (Bool) -> ()) {
        if let condition = UserDefaults.standard.value(forKey: UserDefaultsKeys.firstLaunch.rawValue) as? Bool {
            let domain = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectDomainUser.rawValue)
            getAllUserInstall { installs in
                if installs != nil, installs != [], domain == nil {
                    completion(true)
                    self.logOutUser(completion: { _ in })
                }
                if !KeychainManager.token.isEmpty {
                    completion(condition)
                } else {
                    completion(true)
                }
            }
        } else {
            completion(true)
        }
        
        networking.refreshAccessToken { [weak self] _ in
            self?.userNetworking.preloadUserData { _,_,_ in }
        }
    }
    
    /// User authentication check on Webasyst server
    /// - Parameter completion: updating the user token, and checking authorization
    /// - Returns Returns user status in the application (.authorized/.nonAuthorized/.authorizedButNoneInstalls/.networkError(message: String)/.authorizedButProfileIsEmpty/.error(message: String))
    public func checkUserAuth(completion: @escaping (UserStatus) -> ()) {
        networking.refreshAccessToken { [weak self] result in
            if result {
                self?.userNetworking.preloadUserData { status, _, _ in
                    completion(status)
                }
            } else {
                completion(UserStatus.error(message: "not success refresh token"))
            }
        }
    }
    /// A new free WAID contact connected to the opposite application can oppose another existing WAID contact.
    /// - Returns Returns code for merge
    public func mergeTwoAccs(completion: @escaping (Swift.Result<String, Error>) -> Void) {
        userNetworking.mergeTwoAccounts(completion: completion)
    }
    
    public func deleteAccount(completion: @escaping (Swift.Result<Bool, String>) -> ()) {
        userNetworking.deleteAccount(completion: { result in
            completion(result)
        })
    }
    
    /// Getting user install list
    /// - Returns: List of all user installations in UserInstall format (name, clientId, domain, accessToken, url)
    public func getAllUserInstall(_ result: @escaping ([UserInstall]?) -> ()) {
        let installList = profileInstallService?.getInstallList()
        result(installList)
    }
    
    /// Getting user install list from server
    /// - Returns: List of all user installations in UserInstall format (name, clientId, domain, accessToken, url)
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
    
    /// Deletes the installation from the database
    /// - Parameter clientId: clientId install
    public func deleteInstall(_ clientId: String) {
        profileInstallService?.deleteInstall(clientId: clientId)
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
    
    /// Update current user image
    /// - Parameter image: Image to update
    /// - Parameter success: Closure performed after executing the method
    /// - Returns: Result value which can be successfully or errorable
    public func updateUserImage(_ image: UIImage, success: @escaping (Result) -> Void) {
        userNetworking.updateUserAvatar(image) { result in
            success(result)
        }
    }
    
    /// Delete current user image
    /// - Parameter success: Closure performed after executing the method
    /// - Returns: Result value which can be successfully or errorable
    public func deleteUserImage(success: @escaping (Result) -> Void) {
        userNetworking.deleteUserAvatar { result in
            success(result)
        }
    }
    
    /// Change the data of the current user
    /// - Parameter profile: pass the current data model with user information
    /// - Parameter success: Closure performed after executing the method
    /// - Returns: Result value which can be successfully or errorable
    public func changeCurrentUserData(profile: ProfileData, success: @escaping (Swift.Result<ProfileData,Error>) -> Void) {
        userNetworking.changeUserData(profile) { result in
            success(result)
        }
    }
    
    /// Creating a new Webasyst account
    /// - Parameters:
    ///    - bundle: Bundle of the account being created
    ///    - plainId: Plain id of the account being created
    ///    - accountDomain: Domain of the account being created
    ///    - accountName: Name of the account being created
    ///    - completion: Contains a result of creating and renaming of new account. Reutrns client id and url of new account if successed
    public func createWebasystAccount(bundle: String = "teamwork", plainId: String = "X-1312-TEAMWORK-FREE", accountDomain: String? = nil, accountName: String? = nil, completion: @escaping (AccountCreatingResult) -> ()) {
        userNetworking.createWebasystAccount(bundle: bundle, plainId: plainId, accountName: accountName) { [weak self] success, clientId, url in
            if success, let clientId = clientId, let url = url {
                if let accountDomain = accountDomain {
                    self?.userNetworking.renameWebasystAccount(clientId: clientId, domain: accountDomain) { result in
                        switch result {
                        case .success:
                            completion(.successfullyCreated(clientId: clientId, url: url))
                        case .failure(let error):
                            completion(.successfullyCreatedButNotRenamed(clientId: clientId, url: url, renameError: error.localizedDescription))
                        }
                    }
                } else {
                    completion(.successfullyCreated(clientId: clientId, url: url))
                }
            } else {
                completion(.notCreated(error: url))
            }
        }
    }
    
    /// Exit a user from the account and delete all records in the database
    /// - Returns: Boolean value of deauthorization success
    public func logOutUser(completion: @escaping (Bool) -> ()) {
        userNetworking.singUpUser { _ in }
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
