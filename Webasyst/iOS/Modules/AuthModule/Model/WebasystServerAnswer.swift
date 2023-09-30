//
//  WebasystServerAnswer.swift
//  Webasyst
//
//  Created by Леонид Лукашевич on 30.09.2023.
//

import Foundation

public enum WebasystServerAnswer {
    case success(UserStatus)
    case error(String)
}
