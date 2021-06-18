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
    var auth_endpoint: String
    var cloud_expire_date: String
    
    enum CodingKeys: String, CodingKey {
        case id, domain, url
        case auth_endpoint = "authEndpoint"
        case cloud_expire_date = "cloudExpireDate"
    }
}
