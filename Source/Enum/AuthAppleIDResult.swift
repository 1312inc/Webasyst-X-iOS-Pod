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
    case needEmailConfirm(_ email: String?, _ confirmHandler: (EmailConfirmation) -> ())
    
    public struct EmailConfirmation {
        
        public init(_ result: Result, _ successHandler: @escaping (_ success: Bool, _ status: UserStatus?) -> ()) {
            self.result = result
            self.successHandler = successHandler
        }
        
        let result: Result
        let successHandler: (_ success: Bool, _ status: UserStatus?) -> ()
        
        public enum Result {
            case code(String)
            case skip
        }
    }
}

enum AppleIDResponse {
    
    case success(emailConfirm: Bool)
    case error(_ description: String)
}
