//
//  AuthError.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 27.05.2021.
//

import Foundation

/**
 Server response when authentication is requested
 
 *Values*
 
 `success`: Successful request Tokens saved in Keychain.
 
 `no_channels`: Incorrect clientId.
 
 `invalid_client`: Not transmitted code_challenge.
 
 `require_code_challenge`: Not transmitted code_challenge.
 
 `invalid_email`: An invalid string is passed as an email.
 
 `invalid_phone`: An invalid string is passed as the phone.
 
 `request_timeout_limit`: Repeat request sent before timeout expires for repeat request.
 
 `sent_notification_fail`: The server was unable to send the code.
 
 `server_error`: Server error.
 
 `undefined`: Unknown error, in the value error transmits the text of the error.
 
 */
public enum AuthResult {
    case success
    case no_channels
    case invalid_client
    case require_code_challenge
    case invalid_email
    case invalid_phone
    case request_timeout_limit
    case sent_notification_fail
    case server_error
    case undefined(error: String)
}
