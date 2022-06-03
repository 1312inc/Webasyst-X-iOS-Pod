//
//  TokenStatus.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 26.05.2021.
//

import Foundation

/// User status lists (authorized/unauthorized)
public enum UserStatus {
    case authorizedButProfileIsEmpty
    case authorizedButNoneInstalls
    case authorizedButNoneInstallsAndProfileIsEmpty
    case authorized
    case networkError(String)
    case nonAuthorized
    case error(message: String)
}

public enum LicenseStatus: String {
    case success
    case installation_not_found
    case product_not_found
    case product_not_allowed
    case invalid_token_client
}
