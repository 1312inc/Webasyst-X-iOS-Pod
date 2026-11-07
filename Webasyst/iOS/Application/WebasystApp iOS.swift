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
    func oAuthLogin(with merge: Bool = false, with code: String = "", navigationController: UINavigationController, action: @escaping (_ result: WebasystResult<UserStatus>) -> ()) {
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
        networking.oAuthAppleID(authData: authData) { [self] status in
            switch status {
            case .success(let type):
                switch type {
                case .succeess:
                    userNetworking.preloadUserData { [self] res in
                        switch res {
                        case .success(let status):
                            UserDefaults.standard.setValue(false, forKey: UserDefaultsKeys.firstLaunch.rawValue)
                            result(.completed(status))
                        case .failure(let error):
                            checkMissingAuthTokenError(error)
                            result(.completed(.error(error)))
                        }
                    }
                case .needEmailConfirmation(accessToken: let accessToken):
                    let confirmationGeneration = WebasystAuthSession.shared.generation
                    let confirmHandler: (AuthAppleIDResult.EmailConfirmation) -> () = { [self] confirmation in
                        WebasystAuthSession.onMain {
                            guard WebasystAuthSession.shared.isCurrent(confirmationGeneration) else {
                                confirmation.successHandler(false,
                                    WebasystAuthFailure.make(.superseded, generation: confirmationGeneration).error)
                                return
                            }
                            switch confirmation.result {
                            case .code(let code):
                                userNetworking.sendAppleIDEmailConfirmationCode(code, accessToken: accessToken) { [self] result in
                                    switch result {
                                    case .success:
                                        userNetworking.preloadUserData { [self] res in
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
                    }
                    result(.needEmailConfirmation(authData.userEmail, confirmHandler))
                }
            case .error(let error):
                result(.completed(.error(error)))
            }
        }
    }
    
    /// Merge result check
    /// - Parameter completion: The closure performed after the check returns a Bool value about whether the result was successful or not and a description of the error, if there was one.
    func mergeResultCheck(completion: @escaping (WebasystResult<Bool>) -> Void) {
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
        networking.sendConfirmCode(for: type, code) { result in
            guard result else { success(false); return }
            self.userNetworking.preloadUserData { result in
                switch result {
                case .success:
                    UserDefaults.standard.setValue(false, forKey: UserDefaultsKeys.firstLaunch.rawValue)
                    success(true)
                case .failure: success(false)
                }
            }
        }
    }
    
    /// User authentication check on Webasyst server
    /// - Parameter completion: The closure performed after the check returns a Bool value of whether the user is authorized or not.
    func defaultChecking(completion: @escaping (CheckingType) -> ()) {
        WebasystAuthSession.onMain {
            let auth = WebasystAuthSession.shared
            let stamp = auth.generation
            let defaults = UserDefaults.standard
            let firstLaunch = defaults.object(forKey: UserDefaultsKeys.firstLaunch.rawValue) as? Bool
            let knownLogin = defaults.bool(forKey: UserDefaultsKeys.isLoggedIn.rawValue) || firstLaunch == false
            switch KeychainManager.prepareRestoration() {
            case .failure:
                completion(knownLogin && firstLaunch != true ? .authorized : .notAuthorized)
                return
            case .success(true):
                self.userNetworking.restoreTokensFromGroup { success in
                    guard success else { completion(.notRestoredAuthorizaton); return }
                    self.userNetworking.preloadUserData { result in
                        switch result {
                        case .success:
                            defaults.setValue(false, forKey: UserDefaultsKeys.firstLaunch.rawValue)
                            completion(.restoredAuthorization)
                        case .failure: completion(.notRestoredAuthorizaton)
                        }
                    }
                }
                return
            case .success(false): break
            }
            guard firstLaunch != true else { completion(.notAuthorized); return }
            let access = KeychainManager.readToken(.accessToken)
            let refresh = KeychainManager.readToken(.refreshToken)
            if case .failure = access {
                completion(knownLogin ? .authorized : .notAuthorized)
                return
            }
            if case .failure = refresh {
                completion(knownLogin ? .authorized : .notAuthorized)
                return
            }
            let hasAccess: Bool
            let hasRefresh: Bool
            if case .success(let token) = access { hasAccess = !(token ?? "").isEmpty } else { hasAccess = false }
            if case .success(let token) = refresh { hasRefresh = !(token ?? "").isEmpty } else { hasRefresh = false }
            guard hasAccess || hasRefresh else { completion(.notAuthorized); return }
            // Preserve the immediate cached-start contract of existing applications.
            completion(.authorized)
            guard hasRefresh, auth.isCurrent(stamp) else { return }
            self.networking.refreshAccessTokenResult { result in
                switch result {
                case .success:
                    guard auth.isCurrent(stamp) else { return }
                    self.userNetworking.preloadUserData { _ in }
                case .failure(let failure): self.handleRefreshFailure(failure)
                }
            }
        }
    }
    
    /// Force update WAID access token
    /// - Parameter completion: Whether the token was refreshed. Temporary failures retain the session.
    /// Only a confirmed rejection of the current refresh credential signs the user out.
    func refreshAccessToken(_ completion: @escaping (Bool) -> ()) {
        networking.refreshAccessTokenResult { result in
            switch result {
            case .success: completion(true)
            case .failure(let failure):
                self.handleRefreshFailure(failure)
                completion(false)
            }
        }
    }
    
    /// User authentication check on Webasyst server
    /// - Parameter completion: Updating the user token, and checking authorization. Returns user status in the application.
    func checkUserAuth(completion: @escaping (WebasystResult<UserStatus>) -> ()) {
        networking.refreshAccessTokenResult { result in
            switch result {
            case .success:
                self.userNetworking.preloadUserData(completion)
            case .failure(let failure):
                self.handleRefreshFailure(failure)
                completion(.failure(failure.error))
            }
        }
    }
    
    /// A new free WAID contact connected to the opposite application can oppose another existing WAID contact
    /// - Parameter completion: Result with code to merge or error.
    func mergeTwoAccs(completion: @escaping (WebasystResult<String>) -> Void) {
        userNetworking.mergeTwoAccounts(completion)
    }
    
    /// The method sends a request to delete the current account and returns the result
    /// - Parameter completion: Account deletion result or error.
    func deleteAccount(completion: @escaping (WebasystResult<Bool>) -> ()) {
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
    func updateUserImage(_ image: UIImage, success: @escaping (WebasystResult<Bool>) -> Void) {
        userNetworking.updateUserAvatar(image, success)
    }
    
    /// Delete current user image
    /// - Parameter success: Closure performed after executing the method. Result value which can be successfully or errorable.
    func deleteUserImage(success: @escaping (WebasystResult<Bool>) -> Void) {
        userNetworking.deleteUserAvatar(success)
    }
    
    /// Change the data of the current user
    /// - Parameters:
    ///   - profile: Pass the current data model with user information.
    ///   - success: Closure performed after executing the method. Result value which can be successfully or errorable.
    func changeCurrentUserData(profile: ProfileData, success: @escaping (WebasystResult<ProfileData>) -> Void) {
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
        userNetworking.createWebasystAccount(bundle: bundle, plainId: plainId, accountDomain: accountDomain, accountName: accountName) { result in
            switch result {
            case .success(let parameters):
                completion(.successfullyCreated(clientId: parameters.id, url: parameters.url))
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
        performLogout(manual: true)
    }
}

private
extension WebasystApp {
    
    func checkMissingAuthTokenError(_ error: WebasystError) {
        // An access-token failure is not evidence that the refresh credential has been revoked.
        guard error.statusCode == 401 else { return }
        let failure = WebasystAuthFailure(kind: .server, error: error,
            generation: WebasystAuthSession.shared.generation)
        WebasystAuthDiagnostics.record("protectedRequest", outcome: "unauthorized", failure: failure)
    }

    func handleRefreshFailure(_ failure: WebasystAuthFailure) {
        guard failure.kind == .rejected else { return }
        performLogout(manual: false, expected: failure.generation)
    }

    func performLogout(manual: Bool, expected: UInt64? = nil) {
        WebasystAuthSession.shared.invalidate(expected: expected) {
            if manual { self.userNetworking.singUpUser { _ in } }
            self.profileInstallService?.resetInstallList()
            self.profileInstallService?.deleteProfileData()
            let defaults = UserDefaults.standard
            let wasLoggedIn = defaults.bool(forKey: UserDefaultsKeys.isLoggedIn.rawValue)
            if let domain = Bundle.main.bundleIdentifier { defaults.removePersistentDomain(forName: domain) }
            defaults.set(true, forKey: UserDefaultsKeys.firstLaunch.rawValue)
            if wasLoggedIn { defaults.set(true, forKey: UserDefaultsKeys.isLoggedIn.rawValue) }
            if manual { KeychainManager.deleteAll() } else { KeychainManager.deleteLocal() }
            NotificationCenter.default.post(name: .webasystDidLoggedOut, object: nil)
        }
    }
}
