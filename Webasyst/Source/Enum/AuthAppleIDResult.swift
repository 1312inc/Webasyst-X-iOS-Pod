//
//  AuthAppleIDResult.swift
//  Pods-Webasyst_Example
//
//  Created by Леонид Лукашевич on 14.03.2023.
//

import Foundation


/// Result of authorization. May be in state 'completed' or 'needEmailConfirm'. Completed state returns UserStatus. NeedEmailConfirm state has two parameters:
/// - Parameters:
///    - completed: This state returns UserStatus parameter
///    - needEmailConfirm: This state is required to confirm or cancel email confirmation
public enum AuthAppleIDResult {
    
    case completed(_ status: UserStatus)
    case needEmailConfirmation(_ email: String?, _ confirmHandler: (EmailConfirmation) -> ())
    
    public struct EmailConfirmation {
        
        public init(_ result: Result, _ successHandler: @escaping (_ success: Bool, _ errorDescription: String?) -> ()) {
            self.result = result
            self.successHandler = successHandler
        }
        
        let result: Result
        let successHandler: (_ success: Bool, _ errorDescription: String?) -> ()
        
        public enum Result {
            case code(String)
            case logout
        }
    }
}

enum AppleIDResponse {
    
    case success(_ type: SuccessType)
    case error(_ description: String)
    
    enum SuccessType {
        case needEmailConfirmation(accessToken: Data)
        case succeess
    }
}
