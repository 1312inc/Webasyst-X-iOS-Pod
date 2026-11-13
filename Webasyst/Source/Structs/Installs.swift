//
//  Installs.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 26.05.2021.
//

import Foundation

/// Structure of the settings
public struct Installs: Decodable {
    public var accessToken: String
    public var clientId: String
    public var domain: String
    public var name: String
    public var url: String
}

/// Structure of the settings list
public struct UserInstallCodable: Decodable {
    public var name: String?
    public var domain: String
    public var id: String
    public var accessToken: String?
    public var url: String
    public var image: Data?
    public var cloudPlanId: String?
    public var cloudExpireDate: String?
    public var cloudTrial: Bool?
    
    enum CodingKeys: String, CodingKey {
        case name, domain, id, accessToken, url, image
        case cloudPlanId = "cloud_plan_id"
        case cloudExpireDate = "cloud_expire_date"
        case cloudTrial = "cloud_trial"
    }
}

/// An installation listed by Webasyst ID, independently of its locally saved credentials.
public struct WebasystInstallationCatalogEntry {
    public let metadata: UserInstallCodable
    public let isCheckingAccess: Bool
    public let logoText: String?
    public let logoTextColor: String?
}

public extension Notification.Name {
    /// The WAID catalog or an installation's connection state changed. Delivered on the main queue.
    static let webasystInstallationsDidChange = Notification.Name("Webasyst_installations_did_change")
}

/// Structure of the settings list
public struct UserInstall: Decodable, Equatable {
    public var name: String?
    public var domain: String
    public var id: String
    public var accessToken: String?
    public var url: String
    public var image: Data?
    public var imageLogo: Bool?
    public var logoText: String
    public var logoTextColor: String
    public var cloudPlanId: String?
    public var cloudExpireDate: String?
    public var cloudTrial: Bool?
}

