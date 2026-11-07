//
//  WebasystNetworking.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 13.05.2021.
//

import Foundation

public typealias Parameters = [String: String]

internal class WebasystNetworking: WebasystNetworkingManager {
    
    private static var disposablePasswordAuth: String?
    /// Generating a temporary password for user authentication
    /// - Parameter len: Length of the required password
    /// - Returns: Returns the password in string representation
    private func generatePasswordHash(_ len: Int) -> String {
        let pswdChars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890")
        let rndPswd = String((0..<len).map{ _ in pswdChars[Int(arc4random_uniform(UInt32(pswdChars.count)))]})
        WebasystNetworking.disposablePasswordAuth = rndPswd
        return rndPswd
    }
    
    /// Building a request for user authorization
    /// - Returns: Returns authorization request
    internal func buildAuthRequest(_ code: String) -> URLRequest? {
        WebasystAuthSession.shared.beginAuthorization()
        
        guard let config = WebasystApp.config else {
            print(NSError(domain: "Webasyst error(method: buildAuthRequest): Webasyst ID app Client Id is invalid. Please contact the app developer.", code: 400, userInfo: nil))
            return nil
        }
        
        var paramRequest: Parameters = [
            "response_type": "code",
            "client_id": config.clientId,
            "scope": "profile:write token:\(config.scope)",
            "redirect_uri": "\(config.bundleId)://oidc_callback",
            "state": config.bundleId,
            "code_challenge": "\(self.generatePasswordHash(64))",
            "code_challenge_method": "plain",
            "device_id": getDeviceId()
        ]
        if !code.isEmpty {
            paramRequest["change_user"] = "1"
            paramRequest["mergecode"] = code
        }
        
        guard let urlRequest = buildWebasystUrl("/id/oauth2/auth/code", parameters: paramRequest) else { return nil }
        
        var request = URLRequest(url: urlRequest)
        request.httpMethod = "GET"
        return request
    }
    
    /// Method for obtaining authorisation code without a browser
    /// - Parameters:
    ///   - value: Phone number or email
    ///   - type: Value type(.email/.phone)
    ///   - success: Closure performed after the method has been executed
    /// - Returns: Status of code sent to the user by email or text message, see AuthResult documentation for a detailed description of statuses
    internal func getAuthCode(_ value: String, type: AuthType, success: @escaping (AuthResult) -> ()) {
        let generation = WebasystAuthSession.shared.beginAuthorization()
        
        guard let config = WebasystApp.config else {
            let loc = WebasystApp.getDefaultLocalizedString(withKey: "error.missedConfig")
            let webasystError = WebasystError(localizedError: loc)
            let errorModel = ErrorTypeModel(error: webasystError, type: .standart(), methodName: "getAuthCode")
            let error = getError(errorModel)
            success(.undefined(error: error))
            return
        }
        
        var parametersRequest: Parameters = [
            "client_id": config.clientId,
            "device_id": getDeviceId(),
            "code_challenge": "\(self.generatePasswordHash(64))",
            "code_challenge_method": "plain",
            "scope": "profile:write token:\(config.scope)",
            "locale": "\(NSLocale.current.identifier)"
        ]
        
        switch type {
        case .phone(let isRepeated):
            parametersRequest["phone"] = value
            if isRepeated {
                parametersRequest["is_repeated"] = "true"
            }
        case .email:
            parametersRequest["email"] = value
        }
        
        guard let url = self.buildWebasystUrl("/id/oauth2/auth/headless/code/", parameters: [:]) else {
            let loc = WebasystApp.getDefaultLocalizedString(withKey: "error.urlGeneration")
            let webasystError = WebasystError(localizedError: loc)
            let errorModel = ErrorTypeModel(error: webasystError, type: .standart(), methodName: "getAuthCode")
            let error = getError(errorModel)
            success(.undefined(error: error))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        do {
            try request.setMultipartFormData(parametersRequest, encoding: String.Encoding.utf8)
        } catch let error {
            let loc = WebasystApp.getDefaultLocalizedString(withKey: "error.multipartFormDataGeneration")
                .replacingOccurrences(of: "@DESC", with: error.localizedDescription)
            let webasystError = WebasystError(localizedError: loc)
            let errorModel = ErrorTypeModel(error: webasystError, type: .standart(), methodName: "getAuthCode")
            let error = getError(errorModel)
            success(.undefined(error: error))
            return
        }
        
        createDataTaskSession(request, generation: generation) { [self] response in
            
            switch response {
            case .success(let result):
                let statusCode = result.statusCode
                
                switch statusCode {
                case 200...299:
                    success(.success)
                default:
                    success(.server_error)
                }
            case .failure(let error):
                let statusCode = error.statusCode
                let errorValue = error.errorValue
                
                if let statusCode {
                    switch statusCode {
                    case 400:
                        if let errorValue {
                            switch errorValue {
                            case "no_channels":
                                success(.no_channels)
                            case "invalid_client":
                                success(.invalid_client)
                            case "require_code_challenge":
                                success(.require_code_challenge)
                            case "invalid_email":
                                success(.invalid_email)
                            case "invalid_phone":
                                success(.invalid_phone)
                            default:
                                let errorModel = ErrorTypeModel(error: error, type: .standart(), methodName: "getAuthCode")
                                let error = getError(errorModel)
                                success(.undefined(error: error))
                            }
                        } else {
                            let errorModel = ErrorTypeModel(error: error, type: .standart(), methodName: "getAuthCode")
                            let error = getError(errorModel)
                            success(.undefined(error: error))
                        }
                    case 408:
                        if let errorValue {
                            switch errorValue {
                            case "request_timeout_limit":
                                success(.request_timeout_limit)
                            default:
                                let errorModel = ErrorTypeModel(error: error, type: .standart(), methodName: "getAuthCode")
                                let error = getError(errorModel)
                                success(.undefined(error: error))
                            }
                        } else {
                            let errorModel = ErrorTypeModel(error: error, type: .standart(), methodName: "getAuthCode")
                            let error = getError(errorModel)
                            success(.undefined(error: error))
                        }
                    case 500:
                        if let errorValue {
                            switch errorValue {
                            case "sent_notification_fail":
                                success(.sent_notification_fail)
                            case "server_error":
                                success(.server_error)
                            default:
                                let errorModel = ErrorTypeModel(error: error, type: .standart(), methodName: "getAuthCode")
                                let error = getError(errorModel)
                                success(.undefined(error: error))
                            }
                        } else {
                            let errorModel = ErrorTypeModel(error: error, type: .standart(), methodName: "getAuthCode")
                            let error = getError(errorModel)
                            success(.undefined(error: error))
                        }
                    default:
                        success(.server_error)
                    }
                } else {
                    let errorModel = ErrorTypeModel(error: error, type: .standart(), methodName: "getAuthCode")
                    let error = getError(errorModel)
                    success(.undefined(error: error))
                }
            }
        }
    }
    
    /// Authorization in Webasyst using Apple ID
    /// - Parameters:
    ///    - authData: Authorization data sent by the Apple ID authorization controller
    ///    - completion: success flag and optional error description
    internal func oAuthAppleID(authData: AuthAppleIDData, completion: @escaping (AppleIDResponse) -> ()) {
        let generation = WebasystAuthSession.shared.beginAuthorization()
        
        guard let config = WebasystApp.config else {
            let loc = WebasystApp.getDefaultLocalizedString(withKey: "error.missedConfig")
            let webasystError = WebasystError(localizedError: loc)
            let errorModel = ErrorTypeModel(error: webasystError, type: .standart(), methodName: "oAuthAppleID")
            let error = getError(errorModel)
            completion(.error(error))
            return
        }
        
        var parametersRequest: Parameters = [
            "client_id": config.clientId,
            "device_id": getDeviceId(),
            "scope": "profile:write token:\(config.scope)",
            "user_identifier": authData.userIdentifier,
            "identity_token": authData.identityToken,
            "authorization_code": authData.authorizationCode,
            "email_verified": "\(authData.isRealUserStatus)",
            "locale": "\(NSLocale.current.identifier)"
        ]
        
        if let firstName = authData.userFirstName {
            parametersRequest["firstname"] = firstName
        }
        if let lastName = authData.userLastName {
            parametersRequest["lastname"] = lastName
        }
        if let email = authData.userEmail {
            var isPrivate: Bool
            if email.contains("@privaterelay.appleid.com") {
                isPrivate = true
            } else {
                isPrivate = false
            }
            parametersRequest["is_private_email"] = "\(isPrivate)"
            parametersRequest["email"] = email
        }
        
        guard let url = buildWebasystUrl("/id/oauth2/auth/apple/", parameters: [:]) else {
            let loc = WebasystApp.getDefaultLocalizedString(withKey: "error.urlGeneration")
            let webasystError = WebasystError(localizedError: loc)
            let errorModel = ErrorTypeModel(error: webasystError, type: .standart(), methodName: "oAuthAppleID")
            let error = getError(errorModel)
            completion(.error(error))
            return
        }
        
        var request = URLRequest(url: url)
        
        request.setValue("multipart/form-data", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        do {
            try request.setMultipartFormData(parametersRequest, encoding: String.Encoding.utf8)
        } catch let error {
            let loc = WebasystApp.getDefaultLocalizedString(withKey: "error.multipartFormDataGeneration")
                .replacingOccurrences(of: "@DESC", with: error.localizedDescription)
            let webasystError = WebasystError(localizedError: loc)
            let errorModel = ErrorTypeModel(error: webasystError, type: .standart(), methodName: "oAuthAppleID")
            let error = getError(errorModel)
            completion(.error(error))
            return
        }
        
        WebasystAuthSession.shared.requestTokens(request, generation: generation, operation: "appleID") { result in
            switch result {
            case .success(let tokens):
                if tokens.email_confirm == true {
                    completion(.success(.needEmailConfirmation(accessToken: Data("Bearer \(tokens.access_token)".utf8))))
                } else {
                    switch WebasystAuthSession.shared.accept(tokens, generation: generation) {
                    case .success: completion(.success(.succeess))
                    case .failure(let failure): completion(.error(failure.error))
                    }
                }
            case .failure(let failure): completion(.error(failure.error))
            }
        }
    }
    

    /// Sending a confirmation code after calling the getAuthCode method or after reading qr-code
    /// - Parameters:
    ///   - type: Type of confirmation code
    ///   - code: Code received by user by e-mail or text message
    ///   - success: Closure performed after the method has been executed
    /// - Returns: Bool value whether the server has accepted the code, if true then the tokens are saved in the Keychain
    internal func sendConfirmCode(for type: AuthCodeType, _ code: String, success: @escaping (Bool) -> ()) {
        let auth = WebasystAuthSession.shared
        let generation = auth.beginAuthorization()
        guard let config = WebasystApp.config else { success(false); return }
        var parameters: Parameters = ["client_id": config.clientId, "device_id": getDeviceId(), "code": code]
        let path: String
        switch type {
        case .phone:
            guard let verifier = WebasystNetworking.disposablePasswordAuth else { success(false); return }
            path = "/id/oauth2/auth/headless/token/"
            parameters["code_verifier"] = verifier
        case .qr:
            path = "/id/oauth2/auth/qr/token/"
            parameters["scope"] = "profile:write token:\(config.scope)"
        }
        guard let url = buildWebasystUrl(path, parameters: [:]) else { success(false); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        do { try request.setMultipartFormData(parameters, encoding: .utf8) }
        catch { success(false); return }
        auth.requestTokens(request, generation: generation, operation: "confirmCode") { result in
            switch result {
            case .success(let tokens):
                if case .success = auth.accept(tokens, generation: generation) { success(true) }
                else { success(false) }
            case .failure: success(false)
            }
        }
    }
    
    /// Getting a permanent Webasyst token
    /// - Parameters:
    ///   - authCode: OAuth code from the server
    ///   - stateString: state value from the server
    ///   - completion: Result of a request to the server
    func getAccessToken(_ authCode: String, stateString: String, completion: @escaping (Bool) -> Void) {
        getAccessTokenResult(authCode, stateString: stateString) { result in
            if case .success = result { completion(true) } else { completion(false) }
        }
    }

    /// Keep the original Bool adapter while passing the actual failure to the OAuth screen.
    func getAccessTokenResult(_ authCode: String, stateString: String,
                              completion: @escaping (WebasystAuthSession.RefreshResult) -> Void) {
        let auth = WebasystAuthSession.shared
        let generation = auth.beginAuthorization()
        guard let verifier = WebasystNetworking.disposablePasswordAuth,
              let config = WebasystApp.config,
              let url = buildWebasystUrl("/id/oauth2/auth/token", parameters: [:]) else {
            completion(.failure(.make(.configuration, generation: generation)))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        do {
            try request.setMultipartFormData(["grant_type": "authorization_code", "code": authCode,
                "redirect_uri": "\(config.bundleId)://oidc_callback", "client_id": config.clientId,
                "code_verifier": verifier, "device_id": getDeviceId()], encoding: .utf8)
        } catch { completion(.failure(.make(.configuration, generation: generation))); return }
        auth.requestTokens(request, generation: generation, operation: "oauthCode") { result in
            switch result {
            case .success(let tokens):
                completion(auth.accept(tokens, generation: generation))
            case .failure(let failure): completion(.failure(failure))
            }
        }
    }
    
    /// Token update method on the WAID server
    /// - Parameter completion: Short-circuiting after work methods
    /// - Returns: Returns the boolean value of token update success
    internal func refreshAccessToken(completion: @escaping (Bool) -> ()) {
        refreshAccessTokenResult { result in
            if case .success = result { completion(true) } else { completion(false) }
        }
    }

    internal func refreshAccessTokenResult(_ completion: @escaping (WebasystAuthSession.RefreshResult) -> Void) {
        WebasystAuthSession.shared.refreshAccessToken(completion)
    }
}
