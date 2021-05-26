//
//  File.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 26.05.2021.
//

import Foundation

enum ImageType: Decodable {
    case image, gradient
    case unknown(value: String)
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let status = try? container.decode(String.self)
        switch status {
        case "image": self = .image
        case "gradient": self = .gradient
        default:
            self = .unknown(value: status ?? "unknown")
        }
    }
}
