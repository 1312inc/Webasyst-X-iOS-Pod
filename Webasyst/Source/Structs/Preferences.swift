//
//  Preference.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 25.06.2021.
//

import Foundation

internal struct Preferences: Codable {
    var clientId: String
    var host: String
    var scope: String
}
