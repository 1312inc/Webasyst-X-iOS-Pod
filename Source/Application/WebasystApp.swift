//
//  Webasyst.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 12.05.2021.
//

import UIKit

/// List of token types
public enum TokenType {
    case access
    case refresh
}

/// User status lists (authorized/unauthorized)
public enum UserStatus {
    case authorized
    case nonAuthorized
    case error(message: String)
}

/// User profile data structure
public struct ProfileData {
    public let name: String
    public let firstname: String
    public let lastname: String
    public let middlename: String
    public let email: String
    public let userpic_original_crop: Data?
    
    public init(name: String, firstname: String, lastname: String, middlename: String, email: String, userpic_original_crop: Data?) {
        self.name = name
        self.firstname = firstname
        self.lastname = lastname
        self.middlename = middlename
        self.email = email
        self.userpic_original_crop = userpic_original_crop
    }
}

public struct Installs: Codable {
    public var accessToken: String
    public var clientId: String
    public var domain: String
    public var name: String
    public var url: String
}

/// Structure of the settings list
public struct UserInstall: Codable {
    
    public var name: String?
    public var domain: String
    public var id: String
    public var accessToken: String?
    public var url: String
    public var image: Data?
}

public class WebasystApp {
    
    internal static var config: WebasystConfig?
    
    public init() {}
    
    /// Webasyst library configuration method
    /// - Parameters:
    ///   - bundleId: Bundle Id of your application, required for authorization on the server
    ///   - clientId: Client Id Вашего приложения
    ///   - host: application server host
    public static func configure(clientId: String, host: String, scope: String) {
        if scope.contains("webasyst") {
            config = WebasystConfig(clientId: clientId, host: host, scope: scope)
        } else {
            config = WebasystConfig(clientId: clientId, host: host, scope: "\(scope),webasyst")
        }
        
    }
    
    /// A method for getting Webasyst tokens
    /// - Parameter tokenType: Type of token (Access Token or Refresh Token)
    /// - Returns: Requested token in string format
    public static func getToken(_ tokenType: TokenType) -> String? {
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
    public static func authWebasyst(navigationController: UINavigationController, action: @escaping ((_ result: WebasystServerAnswer) -> ())) {
        let coordinator = AuthCoordinator(navigationController)
        coordinator.start()
        let success: ((_ action: WebasystServerAnswer) -> Void) = { success in
            switch success {
            case .success:
                WebasystUserNetworking().preloadUserData { text, percentLoad, status in
                    if status {
                        print(text, percentLoad, status)
                        action(WebasystServerAnswer.success)
                    } else {
                        print(text, percentLoad, status)
                        action(WebasystServerAnswer.error(error: text))
                    }
                }
            case .error(error: let error):
                action(WebasystServerAnswer.error(error: error))
            }
        }
        coordinator.action = success
    }
    
    /// User authentication check on Webasyst server
    /// - Parameter completion: The closure performed after the check returns a Bool value of whether the user is authorized or not
    public static func checkUserAuth(completion: @escaping (UserStatus) -> ()) {
        
        let accessToken = KeychainManager.load(key: "accessToken")
        
        if accessToken != nil {
            WebasystUserNetworking().preloadUserData { text, percentLoad, status in
                if status {
                    print(text, percentLoad, status)
                    completion(UserStatus.authorized)
                } else {
                    print(text, percentLoad, status)
                    completion(UserStatus.error(message: text))
                }
            }
        } else {
            completion(UserStatus.nonAuthorized)
        }
    }
    
    /// Getting user install list
    /// - Returns: List of all user installations in UserInstall format (name, clientId, domain, accessToken, url)
    public static func getAllUserInstall(_ result: @escaping ([UserInstall]?) -> ()) {
        let installList = WebasystDataModel()?.getInstallList()
        result(installList)
    }
    
    /// Obtaining user installation
    /// - Parameter clientId: clientId setting
    /// - Returns: Installation in User Install format 
    public static func getUserInstall(_ clientId: String) -> UserInstall? {
        let installRequest = WebasystDataModel()?.getInstall(with: clientId)
        guard let install = installRequest else {
            return nil
        }
        return install
    }
    
    /// Удаляет установку из базы данных
    /// - Parameter clientId: clientId install
    public static func deleteInstall(_ clientId: String) {
        WebasystDataModel()?.deleteInstall(clientId: clientId)
    }
    
    /// Returns user profile data
    /// - Returns: User profile data in ProfileData format
    public static func getProfileData() -> ProfileData? {
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
