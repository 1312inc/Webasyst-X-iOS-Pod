//
//  UserData.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 26.05.2021.
//

import Foundation

public struct UserData: Codable {
    public let name: String
    public let firstname: String
    public let lastname: String
    public let middlename: String
    public let email: [Connectivity]
    public let phone: [Connectivity]
    public let userpic_original_crop: String
}

public struct Connectivity: Codable {
    public let value: String
}
