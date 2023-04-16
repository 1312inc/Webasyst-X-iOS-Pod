//
//  AccountCreatingResult.swift
//  Pods
//
//  Created by Леонид Лукашевич on 16.04.2023.
//

import Foundation

public enum AccountCreatingResult {
    case successfullyCreated(clientId: String, url: String)
    case successfullyCreatedButNotRenamed(clientId: String, url: String, renameError: String)
    case notCreated(error: String?)
}
