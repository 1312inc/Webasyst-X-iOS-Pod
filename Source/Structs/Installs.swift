//
//  Installs.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 26.05.2021.
//

import Foundation

/// Structure of the settings
public struct Installs: Codable {
    public var accessToken: String
    public var clientId: String
    public var domain: String
    public var name: String
    public var url: String
}

/// Structure of the settings list
public struct UserInstallCodable: Codable {
    public var name: String?
    public var domain: String
    public var id: String
    public var accessToken: String?
    public var url: String
    public var image: Data?
}

/// Structure of the settings list
public struct UserInstall: Codable {
    public var name: String?
    public var domain: String
    public var id: String
    public var accessToken: String?
    public var url: String
    public var image: Data?
    public var imageLogo: Bool?
    public var logoText: String
    public var logoTextColor: String
}
