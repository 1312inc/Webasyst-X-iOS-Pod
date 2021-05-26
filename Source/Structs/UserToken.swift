//
//  UserToken.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 26.05.2021.
//

import Foundation

internal struct UserToken: Codable {
    let access_token: String
    let token_type: String
    let expires_in: Int
    let refresh_token: String
}
