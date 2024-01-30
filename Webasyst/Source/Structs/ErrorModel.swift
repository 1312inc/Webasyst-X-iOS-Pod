//
//  ErrorModel.swift
//  Webasyst
//
//  Created by Леонид Лукашевич on 31.01.2024.
//

import Foundation

internal struct ErrorModel: Codable {
    let error: String?
    let errorDescription: String?
    
    enum CodingKeys: String, CodingKey {
        case error = "error"
        case errorDescription = "error_description"
    }
}
