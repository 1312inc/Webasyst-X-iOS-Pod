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
    case authorizedButNonInstalls
    case authorizedButNonInstallsAndProfileIsEmpty
    case authorized
    case nonAuthorized
    case error(message: String)
}
