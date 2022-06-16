//
//  InstallStatus.swift
//  Webasyst
//
//  Created by Andrey Gubin on 25.05.2022.
//

import Foundation

public enum InstallStatus: String {
    case alreadyInstalled
    case inProgress
    case successfullyInstalled
    case accessDenied
    case app_not_installed
    case undefinedError
}
