//
//  AuthAppleIDData.swift
//  Pods
//
//  Created by Леонид Лукашевич on 23.02.2023.
//

import Foundation

public struct AuthAppleIDData {
    
    public init(userIdentifier: String, authorizationCode: String, identityToken: String, isRealUserStatus: Bool, userFirstName: String?, userLastName: String?, userEmail: String?) {
        
        self.userIdentifier = userIdentifier
        self.authorizationCode = authorizationCode
        self.identityToken = identityToken
        self.isRealUserStatus = isRealUserStatus
        self.userFirstName = userFirstName
        self.userLastName = userLastName
        self.userEmail = userEmail
    }
    
    let userIdentifier: String
    let authorizationCode: String
    let identityToken: String
    let isRealUserStatus: Bool
    let userFirstName: String?
    let userLastName: String?
    let userEmail: String?
}
