//
//  File.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 26.05.2021.
//

import Foundation

/// List of token types
public enum TokenType {
    
    case access
    case refresh
    
    // MARK: Parameters
    
    internal var keychainValue: KeychainEnum {
        switch self {
        case .access:
            return .accessToken
        case .refresh:
            return .refreshToken
        }
    }
    
    //
    
}
