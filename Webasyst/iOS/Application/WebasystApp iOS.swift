//
//  WebasystApp iOS.swift
//  Webasyst watchOS
//
//  Created by Леонид Лукашевич on 14.08.2023.
//

import UIKit

extension WebasystApp {
    
    /// Webasyst library configuration method
    public func configure() {
        if let path = Bundle.main.path(forResource: "Webasyst", ofType: "plist"), let xml = FileManager.default.contents(atPath: path), let preferences = try? PropertyListDecoder().decode(Preferences.self, from: xml) {
            if preferences.scope.contains("webasyst") {
                WebasystApp.config = WebasystConfig(clientId: preferences.clientId, host: preferences.host, scope: preferences.scope)
            } else {
                WebasystApp.config = WebasystConfig(clientId: preferences.clientId, host: preferences.host, scope: "\(preferences.scope).webasyst")
            }
        } else {
            print(NSError(domain: "Webasyst error(method: configure): Webasyst configuration error, check if there is a Webasyst.plist file in the root of the project", code: 500, userInfo: nil))
        }
    }
    
    /// Start a confetti animation for selected viewController
    /// - Parameters:
    ///   - viewController: UIViewController for which the confetti animation will be called
    public class func requestFullScreenConfetti(for viewController: UIViewController) {
        ConfettiAnimationView.requestFullScreenAnimation(for: viewController)
    }
    
    /// Webasyst server authorization method
    /// - Parameters:
    ///   - navigationController: UINavigationController to display the OAuth webasyst modal window
    ///   - action: Closure to perform an action after authorization
    @available(*, deprecated, message: "This method is obsolete, use oAuthLogin")
    public func authWebasyst(navigationController: UINavigationController, action: @escaping ((_ result: WebasystServerAnswer) -> ())) {
        let coordinator = AuthCoordinator(navigationController) { [weak self] success in
            switch success {
            case .success:
                action(WebasystServerAnswer.success)
                self?.userNetworking.preloadUserData { _, _, _ in }
            case .error(error: let error):
                action(WebasystServerAnswer.error(error: error))
            }
        }
        coordinator.start()
    }
    
    /// The method presents a webView with a Webasyst authorisation form. After successful completion of the form, the user is authenticated and the user status is returned
    /// - Parameters:
    ///   - merge: Parameter that is responsible for merging accounts
    ///   - code: Parameter responsible for merging accounts, which is obtained from the 'mergeTwoAccs' method
    ///   - navigationController: UINavigationController to display the OAuth webasyst modal window
    ///   - action: Closure to perform an action after authorization with status of user
    public func oAuthLogin(with merge: Bool = false, with code: String = "", navigationController: UINavigationController, action: @escaping ((_ result: UserStatus) -> ())) {
        let coordinator = AuthCoordinator(navigationController) { [weak self] success in
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
        coordinator.start(with: code)
    }
    
    /// Authorization in Webasyst with an Apple ID
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
    /// - Parameter completion: The closure performed after the check returns a Bool value about whether the result was successful or not and a description of the error, if there was one
    public func mergeResultCheck(completion: @escaping (Swift.Result<Bool, String>) -> Void) {
        userNetworking.mergeResultCheck(completion: completion)
    }
    
    /// Method for obtaining authorisation code without a browser
    /// - Parameters:
    ///   - value: Phone number or email
    ///   - type: Value type(.email/.phone)
    ///   - success: Closure performed after the method has been executed. Contains the status of code sent to the user by email or text message, see the AuthResult documentation for a detailed description of the statuses
    public func getAuthCode(_ value: String, type: AuthType, success: @escaping (AuthResult) -> ()) {
        networking.getAuthCode(value, type: type) { result in
            success(result)
        }
    }
    
    /// Sending a confirmation code after calling the getAuthCode method or after reading qr-code
    /// - Parameters:
    ///   - type: Type of confirmation code
    ///   - code: Code received by user by e-mail or text message or qr content
    ///   - success: Closure performed after the method has been executed. Bool value whether the server has accepted the code, if true then the tokens are saved in the Keychain
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
    
    /// User authentication check on Webasyst server
    /// - Parameter completion: The closure performed after the check returns a Bool value of whether the user is authorized or not
    public func defaultChecking(completion: @escaping (Bool) -> ()) {
        if let condition = UserDefaults.standard.value(forKey: UserDefaultsKeys.firstLaunch.rawValue) as? Bool {
            let domain = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectDomainUser.rawValue)
            getAllUserInstall { [weak self] installs in
                if installs != nil, installs != [], domain == nil {
                    completion(true)
                    self?.logOutUser(completion: { _ in })
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
    /// - Parameter completion: Updating the user token, and checking authorization. Returns user status in the application (.authorized/.nonAuthorized/.authorizedButNoneInstalls/.networkError(message: String)/.authorizedButProfileIsEmpty/.error(message: String))
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
    
    /// A new free WAID contact connected to the opposite application can oppose another existing WAID contact
    /// - Parameter completion: Result with code to merge or error
    public func mergeTwoAccs(completion: @escaping (Swift.Result<String, Error>) -> Void) {
        userNetworking.mergeTwoAccounts(completion: completion)
    }
    
    /// The method sends a request to delete the current account and returns the result
    /// - Parameter completion: Account deletion result or error
    public func deleteAccount(completion: @escaping (Swift.Result<Bool, String>) -> ()) {
        userNetworking.deleteAccount(completion: { result in
            completion(result)
        })
    }
    
    /// Deletes the installation from the database
    /// - Parameter clientId: clientId install
    public func deleteInstall(_ clientId: String) {
        profileInstallService?.deleteInstall(clientId: clientId)
    }
    
    /// Update current user image
    /// - Parameters:
    ///   - image: Image to update
    ///   - success: Closure performed after executing the method. Result value which can be successfully or errorable
    public func updateUserImage(_ image: UIImage, success: @escaping (Result) -> Void) {
        userNetworking.updateUserAvatar(image) { result in
            success(result)
        }
    }
    
    /// Delete current user image
    /// - Parameter success: Closure performed after executing the method. Result value which can be successfully or errorable
    public func deleteUserImage(success: @escaping (Result) -> Void) {
        userNetworking.deleteUserAvatar { result in
            success(result)
        }
    }
    
    /// Change the data of the current user
    /// - Parameters:
    ///   - profile: Pass the current data model with user information
    ///   - success: Closure performed after executing the method. Result value which can be successfully or errorable
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
    
    /// Logs out a user from the account and delete all records in the database
    /// - Parameter completion: Boolean value of deauthorization success
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
