//
//  ServerErrorDescriptionType.swift
//  Webasyst
//
//  Created by Леонид Лукашевич on 15.12.2024.
//

enum ServerErrorDescriptionType {
    case unowned(response: ServerResponse)
    case decodingData
    case decodingParameters(domain: String? = nil)
    case standart(domain: String? = nil)
}

