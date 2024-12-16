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
        let tokenData = Data(token.utf8)
        _ = KeychainManager.save(tokenType.keychainValue, data: tokenData)
    }
    
    /// Delete all records in the database
    /// - Parameter completion: Boolean value of deauthorization success.
    func logOutUser(completion: (Bool) -> ()) {
        profileInstallService?.resetInstallList()
        profileInstallService?.deleteProfileData()
        
        KeychainManager.deleteAll()
        
        let isLoggedIn = UserDefaults.standard.bool(forKey: UserDefaultsKeys.isLoggedIn.rawValue)
        
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard.synchronize()
        }
        
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.firstLaunch.rawValue)
        if isLoggedIn {
            UserDefaults.standard.setValue(true, forKey: UserDefaultsKeys.isLoggedIn.rawValue)
        }
        
        completion(true)
    }
}
