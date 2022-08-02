//
//  CreateNewAccount.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 18.06.2021.
//

import Foundation

public struct CreateNewAccount: Codable {
    public var id: String
    public var domain: String
    public var url: String
    public var authEndpoint: String
    public var cloudExpireDate: String
    
    enum CodingKeys: String, CodingKey {
        case id, domain, url
        case authEndpoint = "auth_endpoint"
        case cloudExpireDate = "cloud_expire_date"
    }
}
