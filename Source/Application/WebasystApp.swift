//
//  Webasyst.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 12.05.2021.
//

import UIKit

public enum TokenType {
    case access
    case refresh
}

public enum UserStatus {
    case authorized
    case nonAuthorized
    case error(message: String)
}

public struct UserInstall {
    
    public var name: String
    public var domain: String
    public var clientId: String
    public var accessToken: String
    public var url: String
    
    public init(name: String, url: String, accessToken: String, domain: String, clientId: String) {
        self.name = name
        self.domain = domain
        self.url = domain
        self.accessToken = accessToken
        self.clientId = clientId
    }
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
        config = WebasystConfig(clientId: clientId, host: host, scope: scope)
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
                action(WebasystServerAnswer.success)
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
            WebasystNetworking().refreshAccessToken { success in
                if success {
                    completion(UserStatus.authorized)
                } else {
                    completion(UserStatus.error(message: "WebasystApp Error: Access token is not update"))
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
    public static func getUserInstall(_ clientId: String) -> UserInstall? {
        let installRequest = WebasystDataModel()?.getInstall(with: clientId)
        guard let install = installRequest else {
            return nil
        }
        return install
    }
    
    public static func deleteInstall(_ clientId: String) {
        WebasystDataModel()?.deleteInstall(clientId: clientId)
    }
    
    public static func getUserData() {
        WebasystUserNetworking().getUserData()
    }
    
}
