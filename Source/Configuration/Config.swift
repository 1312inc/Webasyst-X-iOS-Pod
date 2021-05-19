//
//  Config.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 13.05.2021.
//

import Foundation

internal struct WebasystConfig {
    
    var bundleId: String
    var clientId: String
    var host: String
    var scope: String
    
    init(clientId: String, host: String, scope: String) {
        self.bundleId = Bundle.main.bundleIdentifier ?? ""
        self.clientId = clientId
        self.host = host
        self.scope = scope
    }
}

internal enum WebasystDBConfig {
  static var dbFolder = "WebasystAppDataModel"
}
