//
//  CreateNewAccount.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 18.06.2021.
//

import Foundation

struct CreateNewAccount: Codable {
    var id: String
    var domain: String
    var url: String
    var authEndpoint: String
    var cloudExpireDate: String
    
    enum CodingKeys: String, CodingKey {
        case id, domain, url
        case authEndpoint = "auth_endpoint"
        case cloudExpireDate = "cloud_expire_date"
    }
}
