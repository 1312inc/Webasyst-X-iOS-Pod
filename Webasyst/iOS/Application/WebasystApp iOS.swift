import UIKit

public
extension WebasystApp {
    
    /// Method to get device id for watchOS webasyst framework configuration
    /// - Returns: iOS device identifier.
    func getDeviceID() -> String {
        networking.getDeviceId()
    }
    
    /// Start a confetti animation for selected viewController
    /// - Parameter viewController: UIViewController for which the confetti animation will be called.
    class func requestFullScreenConfetti(for viewController: UIViewController) {
        ConfettiAnimationView.requestFullScreenAnimation(for: viewController)
    }
    
    /// Webasyst server authorization method
    /// - Parameters:
    ///   - navigationController: UINavigationController to display the OAuth webasyst modal window.
    ///   - action: Closure to perform an action after authorization.
    @available(*, deprecated, message: "This method is obsolete, use oAuthLogin")
    func authWebasyst(navigationController: UINavigationController, action: @escaping (_ result: WebasystServerAnswer) -> ()) {
        coordinator = AuthCoordinator(navigationController) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                UserDefaults.standard.setValue(false, forKey: UserDefaultsKeys.firstLaunch.rawValue)
            case .error(let error):
                checkMissingAuthTokenError(error)
            }
            action(result)
        }
        coordinator?.start()
    }
    
    /// The method presents a webView with a Webasyst authorisation form. After successful completion of the form, the user is authenticated and the user status is returned
    /// - Parameters:
    ///   - merge: Parameter that is responsible for merging accounts.
    ///   - code: Parameter responsible for merging accounts, which is obtained from the 'mergeTwoAccs' method.
    ///   - navigationController: UINavigationController to display the OAuth webasyst modal window.
    ///   - action: Closure to perform an action after authorization with status of user.
    func oAuthLogin(with merge: Bool = false, with code: String = "", navigationController: UINavigationController, action: @escaping (_ result: Result<UserStatus, String>) -> ()) {
        coordinator = AuthCoordinator(navigationController) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                UserDefaults.standard.setValue("", forKey: UserDefaultsKeys.selectDomainUser.rawValue)
                userNetworking.preloadUserData { result in
                    switch result {
                    case .success(let status):
                        UserDefaults.standard.setValue(false, forKey: UserDefaultsKeys.firstLaunch.rawValue)
                        action(.success(status))
                    case .failure(let error):
                        action(.failure(error))
                    }
                }
            case .error(let error):
                checkMissingAuthTokenError(error)
                action(.failure(error))
            }
        }
        coordinator?.start(with: code)
    }
    
    /// Authorization in Webasyst with an Apple ID
    /// - Parameters:
    ///    - authData: Authorization data sent by the Apple ID authorization controller.
    ///    - result: Closure with result of authorization.
    func oAuthAppleID(authData: AuthAppleIDData, result: @escaping (_ result: AuthAppleIDResult) -> ()) {
        networking.oAuthAppleID(authData: authData) { [weak self] status in
            guard let self = self else { return }
            switch status {
            case .success(let type):
                switch type {
                case .succeess:
                    userNetworking.preloadUserData { [weak self] res in
                        guard let self = self else { return }
                        switch res {
                        case .success(let status):
                            UserDefaults.standard.setValue(false, forKey: UserDefaultsKeys.firstLaunch.rawValue)
                            result(.completed(status))
                        case .failure(let error):
                            checkMissingAuthTokenError(error)
                            result(.completed(.error(message: error)))
                        }
                    }
                case .needEmailConfirmation(accessToken: let accessToken):
                    let confirmHandler: (AuthAppleIDResult.EmailConfirmation) -> () = { [weak self] confirmation in
                        guard let self = self else { return }
                        switch confirmation.result {
                        case .code(let code):
                            userNetworking.sendAppleIDEmailConfirmationCode(code, accessToken: accessToken) { [weak self] result in
                                guard let self = self else { return }
                                switch result {
                                case .success:
                                    userNetworking.preloadUserData { [weak self] res in
                                        guard let self = self else { return }
                                        switch res {
                                        case .success:
                                            UserDefaults.standard.setValue(false, forKey: UserDefaultsKeys.firstLaunch.rawValue)
                                            confirmation.successHandler(true, nil)
                                        case .failure(let error):
                                            checkMissingAuthTokenError(error)
                                            confirmation.successHandler(false, error)
                                        }
                                    }
                                case .failure(let error):
                                    confirmation.successHandler(false, error)
                                }
                            }
                        case .logout:
                            logOutUser()
                            confirmation.successHandler(true, nil)
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
    /// - Parameter completion: The closure performed after the check returns a Bool value about whether the result was successful or not and a description of the error, if there was one.
    func mergeResultCheck(completion: @escaping (Result<Bool, String>) -> Void) {
        userNetworking.mergeResultCheck(completion)
    }
    
    /// Method for obtaining authorisation code without a browser
    /// - Parameters:
    ///   - value: Phone number or email.
    ///   - type: Value type.
    ///   - success: Closure performed after the method has been executed. Contains the status of code sent to the user by email or text message, see the AuthResult documentation for a detailed description of the statuses.
    func getAuthCode(_ value: String, type: AuthType, success: @escaping (AuthResult) -> ()) {
        networking.getAuthCode(value, type: type, success: success)
    }
    
    /// Sending a confirmation code after calling the getAuthCode method or after reading qr-code
    /// - Parameters:
    ///   - type: Type of confirmation code.
    ///   - code: Code received by user by e-mail or text message or qr content.
    ///   - success: Closure performed after the method has been executed. Bool value whether the server has accepted the code, if true then the tokens are saved in the Keychain.
    func sendConfirmCode(for type: AuthCodeType = .phone, _ code: String, success: @escaping (Bool) -> ()) {
        networking.sendConfirmCode(for: type, code) { [weak self] result in
            guard let self = self else { return }
            if result {
                userNetworking.preloadUserData { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success:
                        UserDefaults.standard.setValue(false, forKey: UserDefaultsKeys.firstLaunch.rawValue)
                        success(true)
                    case .failure(let error):
                        checkMissingAuthTokenError(error)
                        success(false)
                    }
                }
            } else {
                success(false)
            }
        }
    }
    
    /// User authentication check on Webasyst server
    /// - Parameter completion: The closure performed after the check returns a Bool value of whether the user is authorized or not.
    func defaultChecking(completion: @escaping (Bool) -> ()) {
        let restorationSuccess = KeychainManager.checkRestorationSuccess()
        
        if restorationSuccess {
            UserDefaults.standard.setValue(false, forKey: UserDefaultsKeys.firstLaunch.rawValue)
        }
        
        if let condition = UserDefaults.standard.value(forKey: UserDefaultsKeys.firstLaunch.rawValue) as? Bool {
            let domain = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectDomainUser.rawValue)
            
            let installs = getAllUserInstall()
            
            if installs != nil, installs != [], domain == nil {
                completion(true)
                logOutUser()
            }
            
            if !KeychainManager.getToken(.accessToken).isEmpty {
                completion(condition)
            } else {
                completion(true)
                logOutUser()
            }
        } else {
            completion(true)
        }
        
        networking.refreshAccessToken { [weak self] success in
            guard let self = self else { return }
            if success {
                userNetworking.preloadUserData { [weak self] result in
                    guard let self = self else { return }
                    if case .failure(let error) = result {
                        checkMissingAuthTokenError(error)
                    }
                }
            } else {
                logOutUser()
            }
        }
    }
    
    /// Force update WAID access token
    /// - Parameter completion: The result of updating the access token. If the update failed, the user will log out.
    func refreshAccessToken(_ completion: @escaping (Bool) -> ()) {
        networking.refreshAccessToken { [weak self] success in
            guard let self = self else { return }
            completion(success)
            if !success {
                logOutUser()
            }
        }
    }
    
    /// User authentication check on Webasyst server
    /// - Parameter completion: Updating the user token, and checking authorization. Returns user status in the application.
    func checkUserAuth(completion: @escaping (Result<UserStatus, String>) -> ()) {
        networking.refreshAccessToken { [weak self] result in
            guard let self = self else { return }
            if result {
                userNetworking.preloadUserData { [weak self] result in
                    guard let self = self else { return }
                    if case .failure(let error) = result {
                        checkMissingAuthTokenError(error)
                    }
                    completion(result)
                }
            } else {
                logOutUser()
                completion(.failure("Not success refresh token."))
            }
        }
    }
    
    /// A new free WAID contact connected to the opposite application can oppose another existing WAID contact
    /// - Parameter completion: Result with code to merge or error.
    func mergeTwoAccs(completion: @escaping (Result<String, Error>) -> Void) {
        userNetworking.mergeTwoAccounts(completion)
    }
    
    /// The method sends a request to delete the current account and returns the result
    /// - Parameter completion: Account deletion result or error.
    func deleteAccount(completion: @escaping (Result<Bool, String>) -> ()) {
        userNetworking.deleteAccount(completion)
    }
    
    /// Deletes the installation from the database
    /// - Parameter clientId: clientId install.
    func deleteInstall(_ clientId: String) {
        profileInstallService?.deleteInstall(clientId: clientId)
    }
    
    /// Update current user image
    /// - Parameters:
    ///   - image: Image to update.
    ///   - success: Closure performed after executing the method. Result value which can be successfully or errorable.
    func updateUserImage(_ image: UIImage, success: @escaping (Result<Bool, String>) -> Void) {
        userNetworking.updateUserAvatar(image, success)
    }
    
    /// Delete current user image
    /// - Parameter success: Closure performed after executing the method. Result value which can be successfully or errorable.
    func deleteUserImage(success: @escaping (Result<Bool, String>) -> Void) {
        userNetworking.deleteUserAvatar(success)
    }
    
    /// Change the data of the current user
    /// - Parameters:
    ///   - profile: Pass the current data model with user information.
    ///   - success: Closure performed after executing the method. Result value which can be successfully or errorable.
    func changeCurrentUserData(profile: ProfileData, success: @escaping (Result<ProfileData,Error>) -> Void) {
        userNetworking.changeUserData(profile, success)
    }
    
    /// Creating a new Webasyst account
    /// - Parameters:
    ///    - bundle: Bundle of the account being created.
    ///    - plainId: Plain id of the account being created.
    ///    - accountDomain: Domain of the account being created.
    ///    - accountName: Name of the account being created.
    ///    - completion: Contains a result of creating and renaming of new account. Reutrns client id and url of new account if successed.
    func createWebasystAccount(bundle: String = "teamwork", plainId: String = "X-1312-TEAMWORK-FREE", accountDomain: String? = nil, accountName: String? = nil, _ completion: @escaping (AccountCreatingResult) -> ()) {
        userNetworking.createWebasystAccount(bundle: bundle, plainId: plainId, accountName: accountName) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let parameters):
                if let accountDomain = accountDomain {
                    userNetworking.renameWebasystAccount(clientId: parameters.id, domain: accountDomain) { result in
                        switch result {
                        case .success:
                            completion(.successfullyCreated(clientId: parameters.id, url: parameters.url))
                        case .failure(let error):
                            completion(.successfullyCreatedButNotRenamed(clientId: parameters.id, url: parameters.url, renameError: error))
                        }
                    }
                } else {
                    completion(.successfullyCreated(clientId: parameters.id, url: parameters.url))
                }
            case .failure(let error):
                completion(.notCreated(error: error))
            }
        }
    }
    
    /// Logs out a user from the account and delete all records in the database
    ///
    /// After logging out NotificationCenter posts a message Notification.Name.webasystDidLoggedOut.
    /// - Parameter completion: Boolean value of deauthorization success.
    func logOutUser() {
        userNetworking.singUpUser { _ in }
        
        profileInstallService?.resetInstallList()
        profileInstallService?.deleteProfileData()
        
        KeychainManager.deleteAll()
        
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard.synchronize()
        }
        
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.firstLaunch.rawValue)
        
        NotificationCenter.default.post(name: .webasystDidLoggedOut, object: nil)
    }
}

private
extension WebasystApp {
    
    func checkMissingAuthTokenError(_ error: String) {
        if error == WebasystApp.getDefaultLocalizedString(withKey: "missingAuthToken", comment: "The authentication token is missing.") {
            logOutUser()
        }
    }
}
