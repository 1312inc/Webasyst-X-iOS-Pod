//
//  InstallInfo.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 26.05.2021.
//

import Foundation

internal struct InstallInfo: Decodable {
    var name: String
    var logo: Logo?
}

internal struct Logo: Decodable {
    var mode: ImageType
}

struct LogoGradient: Codable {
    var name: String
    var logo: Gradient?
}

struct Gradient: Codable {
    var gradient: GradientType
}

struct GradientType: Codable {
    var from: String
    var to: String
    var angle: String
}

struct LogoImage: Codable {
    var name: String
    var logo: TypeImage?
}

struct TypeImage: Codable {
    var image: Original
}

struct Original: Codable {
    var original: OriginalImage
}

struct OriginalImage: Codable {
    var url: String
}