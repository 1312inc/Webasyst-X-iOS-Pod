//
//  AuthType.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 27.05.2021.
//

import Foundation

public enum AuthType {
    case phone(isRepeated: Bool = false)
    case email
}
