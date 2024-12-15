/**
 Open class for working with Webasyst
  
 # Usage example
 ```
 let webasyst =  WebasystApp()
 webasyst.configure()
 let accessToken = webasyst.getToken(_ tokenType: .access)
 print(accessToken)
 ```
 */

public class WebasystApp {
    
    
    // MARK: Init
    
    public init() {}
    
    //
    
    
    // MARK: Parameters
    
    static private(set) var config: WebasystConfig?
    
    let profileInstallService = WebasystDataModel()
    let networking = WebasystNetworking()
    let userNetworking = WebasystUserNetworking()
    
    #if os(iOS)
    var coordinator: AuthCoordinator?
    #endif
    
    //
    
    
    // MARK: Methods
    
    /// Webasyst library configuration method
    /// - Parameter deviceID: Device identifier of main Webasyst iOS application. Parameter required for library correctly work on companion applications of the main Webasyst application.
    public func configure(deviceID: String? = nil) {
        if let path = Bundle.main.path(forResource: "Webasyst", ofType: "plist"),
            let xml = FileManager.default.contents(atPath: path),
            let preferences = try? PropertyListDecoder().decode(Preferences.self, from: xml) {
            
            let scope: String
            if preferences.scope.contains("webasyst") {
                scope = preferences.scope
            } else {
                scope = "\(preferences.scope).webasyst"
            }
            
            WebasystApp.config = WebasystConfig(clientId: preferences.clientId, host: preferences.host, scope: scope)
        } else {
            print(NSError(domain: "Webasyst error(method: configure): Webasyst configuration error, check if there is a Webasyst.plist file in the root of the project", code: 500, userInfo: nil))
        }
        
        if let deviceID = deviceID {
            UserDefaults.standard.set(deviceID, forKey: "deviceID")
        }
    }
    
    /// - Returns: Url for local storage.
    public class func url() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("settings")
    }
    
    /// Returns the NSLocalizedString contained in the Webasyst localisation files
    /// - Parameters:
    ///   - key: Parameter for NSLocalizedString method.
    ///   - comment: Parameter for NSLocalizedString method.
    /// - Returns: String returned by NSLocalizedString.
    public class func getDefaultLocalizedString(withKey key: String, comment: String? = nil) -> String {
        return NSLocalizedString(key, bundle: Bundle(for: self), comment: comment ?? key)
    }
    
    /// A method for getting Webasyst tokens
    /// - Parameter tokenType: Type of token.
    /// - Returns: Requested token in string format.
    public func getToken(_ tokenType: TokenType) -> String? {
        let token = KeychainManager.getToken(tokenType.keychainValue)
        guard !token.isEmpty else { return nil }
        return token
    }
    
    /// A method for getting Webasyst tokens
    /// - Parameter tokenType: Type of token.
    /// - Returns: Requested token in string format.
    public static func getToken(_ tokenType: TokenType) -> String? {
        let token = KeychainManager.getToken(tokenType.keychainValue)
        guard !token.isEmpty else { return nil }
        return token
    }
    
    /// App installation
    /// - Parameters:
    ///   - app: Application name.
    ///   - completion: The closure performed after the check returns a Bool value about whether the result was successful or not and a description of the error, if there was one.
    public func checkInstallApp(app: String, completion: @escaping (WebasystResult<String?>) -> ()) {
        userNetworking.checkAppInstall(app: app, completion)
    }
    
    /// Tries to find a free (not tied to the installation) license from the user whose token is accessed by the mobile application. If there is one, then binds it to the installation. Otherwise, it creates a trial product license tied to the installation.
    /// - Parameters:
    ///   - app: Application name.
    ///   - completion: The closure performed after the check returns a Bool value of whether the user is authorized or not.
    public func checkLicense(app: String, completion: @escaping (WebasystResult<String?>) -> ()) {
        userNetworking.checkInstallLicense(app: app, completion)
    }
    
    /// Tries to find a free (not tied to the installation) license from the user whose token is accessed by the mobile application. If there is one, then binds it to the installation. Otherwise, it creates a trial product license tied to the installation.
    /// - Parameters:
    ///   - type: Type of subscription plan.
    ///   - date: Subscription cut-off date.
    ///   - completion: The closure performed after the check returns a Bool value of whether the user is authorized or not.
    public func extendLicense(type: String, date: String, completion: @escaping (WebasystResult<String?>) -> ()) {
        userNetworking.extendLicense(type: type, date: date, completion)
    }
    
    /// Getting user install list
    /// - Returns: List of all user installations in UserInstall format.
    public func getAllUserInstall() -> [UserInstall]? {
        profileInstallService?.getInstallList()
    }
    
    /// Updating and Getting user install list from server
    /// - Parameter completion: List of all user installations in UserInstallCodable format (name, clientId, domain, accessToken, url).
    public func updateUserInstalls(_ result: @escaping ([UserInstallCodable]?) -> ()) {
        userNetworking.getInstallList { [weak self] res in
            guard let self = self else { return }
            switch res {
            case .success(let installs):
                if installs.count == 0 {
                    result(installs)
                } else {
                    let clientIDs = installs.map { $0.id }
                    userNetworking.getAccessTokenApi(clientId: clientIDs) { [weak self] res in
                        guard let self = self else { return }
                        switch res {
                        case .success(let accessToken):
                            userNetworking.getAccessTokenInstall(installs, accessCodes: accessToken) { _ in
                                result(installs)
                            }
                        case .failure:
                            result(nil)
                        }
                    }
                }
            case .failure:
                result(nil)
            }
        }
    }
    
    /// Obtaining user installation
    /// - Parameter clientId: clientId setting.
    /// - Returns: Installation in User Install format.
    public func getUserInstall(_ clientId: String) -> UserInstall? {
        let installRequest = profileInstallService?.getInstall(with: clientId)
        guard let install = installRequest else {
            return nil
        }
        return install
    }
    
    /// Returns user profile data
    /// - Returns: User profile data in ProfileData format.
    public func getProfileData() -> ProfileData? {
        return profileInstallService?.getProfile()
    }
    
    //
}
