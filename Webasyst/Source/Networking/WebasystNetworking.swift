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
    private var queue = DispatchQueue(label: "webAsyst.networking", qos: .background)
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
        
        createDataTaskSession(request) { [weak self] response in
            guard let self else { return }
            
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
        
        createDataTaskSession(request) { [weak self] response in
            guard let self else { return }
            
            switch response {
            case .success(let result):
                let statusCode = result.statusCode
                let data = result.data
                
                do {
                    let authData = try JSONDecoder().decode(UserToken.self, from: data)
                    
                    let accessTokenData = Data("Bearer \(authData.access_token)".utf8)
                    
                    if let emailConfirm = authData.email_confirm, emailConfirm == true {
                        completion(.success(.needEmailConfirmation(accessToken: accessTokenData)))
                    } else {
                        let refreshTokenData = Data(authData.refresh_token.utf8)
                        
                        let accessTokenSuccess = KeychainManager.save(.accessToken, data: accessTokenData)
                        let refreshTokenSuccess = KeychainManager.save(.refreshToken, data: refreshTokenData)
                        
                        if accessTokenSuccess == 0 && refreshTokenSuccess == 0 {
                            completion(.success(.succeess))
                        } else {
                            let loc = WebasystApp.getDefaultLocalizedString(withKey: "error.keychainSave")
                            let webasystError = WebasystError(localizedError: loc, statusCode: statusCode)
                            let errorType = ErrorTypeModel(error: webasystError, type: .standart(), methodName: "oAuthAppleID")
                            let error = getError(errorType)
                            completion(.error(error))
                        }
                    }
                } catch let error {
                    let loc = "\(error)"
                    let webasystError = WebasystError(localizedError: loc, statusCode: statusCode)
                    let errorType = ErrorTypeModel(error: webasystError, type: .decodingData, methodName: "oAuthAppleID")
                    let error = getError(errorType)
                    completion(.error(error))
                }
            case .failure(let error):
                let errorModel = ErrorTypeModel(error: error, type: .standart(), methodName: "oAuthAppleID")
                let error = getError(errorModel)
                completion(.error(error))
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
        
        guard let config = WebasystApp.config else {
            print(NSError(domain: "Webasyst error(method: sendConfirmCode): Webasyst ID app Client Id is invalid. Please contact the app developer.", code: 400, userInfo: nil))
            success(false)
            return
        }
        
        var parametersRequest: Parameters = [
            "client_id": config.clientId,
            "device_id": getDeviceId(),
            "code": code
        ]
        
        var urlString: String
        switch type {
        case .phone:
            guard let passwordHash = WebasystNetworking.disposablePasswordAuth else {
                print(NSError(domain: "Webasyst error(method: sendConfirmCode): Failed to obtain a one-time password", code: 400, userInfo: nil))
                success(false)
                return
            }
            urlString = "/id/oauth2/auth/headless/token/"
            parametersRequest["code_verifier"] = passwordHash
        case .qr:
            urlString = "/id/oauth2/auth/qr/token/"
            parametersRequest["scope"] = "profile:write token:\(config.scope)"
        }
        
        guard let url = buildWebasystUrl(urlString, parameters: [:]) else {
            print(NSError(domain: "Webasyst error(method: sendConfirmCode): Authorisation URL generation error", code: 400, userInfo: nil))
            success(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        do {
            try request.setMultipartFormData(parametersRequest, encoding: String.Encoding.utf8)
        } catch let error {
            print(NSError(domain: "Webasyst error(method: sendConfirmCode): \(error.localizedDescription))'", code: 400, userInfo: nil))
            success(false)
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            
            guard error == nil else {
                print(NSError(domain: "Webasyst error(method: sendConfirmCode): Request error", code: 400, userInfo: nil))
                success(false)
                return
            }
            
            guard let data = data else {
                success(false)
                print(NSError(domain: "Webasyst error(method: sendConfirmCode): Error in receiving the server response body", code: 400, userInfo: nil))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                success(false)
                print(NSError(domain: "Webasyst error(method: sendConfirmCode): Request error", code: 400, userInfo: nil))
                return
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                do {
                    let authData = try JSONDecoder().decode(UserToken.self, from: data)
                    
                    let accessTokenData = Data("Bearer \(authData.access_token)".utf8)
                    let refreshTokenData = Data(authData.refresh_token.utf8)
                    
                    let accessTokenSuccess = KeychainManager.save(.accessToken, data: accessTokenData)
                    let refreshTokenSuccess = KeychainManager.save(.refreshToken, data: refreshTokenData)
                    
                    if accessTokenSuccess == 0 && refreshTokenSuccess == 0 {
                        success(true)
                    }
                } catch let error {
                    success(false)
                    print(NSError(domain: "Webasyst error(method: sendConfirmCode): \(error.localizedDescription)", code: 400, userInfo: nil))
                }
            default:
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if json["error"] != nil {
                            success(false)
                            print(NSError(domain: "Webasyst error(method: sendConfirmCode): \(json["error"] as! String)", code: 400, userInfo: nil))
                        } else {
                            success(false)
                            print(NSError(domain: "Webasyst error(method: sendConfirmCode): undefined server error", code: 400, userInfo: nil))
                        }
                    } else {
                        success(false)
                        print(NSError(domain: "Webasyst error(method: sendConfirmCode): undefined server error", code: 400, userInfo: nil))
                    }
                } catch let error {
                    success(false)
                    print(NSError(domain: "Webasyst error(method: sendConfirmCode): \(error.localizedDescription)", code: 400, userInfo: nil))
                }
            }
            
        }.resume()
    }
    
    /// Getting a permanent Webasyst token
    /// - Parameters:
    ///   - authCode: OAuth code from the server
    ///   - stateString: state value from the server
    ///   - completion: Result of a request to the server
    func getAccessToken(_ authCode: String, stateString: String, completion: @escaping (Bool) -> Void) {
        
        guard let disposablePassword = WebasystNetworking.disposablePasswordAuth else { return }
        guard let config = WebasystApp.config else { return }
        
        let paramRequest: Parameters = [
            "grant_type": "authorization_code",
            "code": authCode,
            "redirect_uri": "\(String(describing: config.bundleId))://oidc_callback",
            "client_id": config.clientId,
            "code_verifier": disposablePassword,
            "device_id": getDeviceId()
        ]
        
        guard let url = buildWebasystUrl("/id/oauth2/auth/token", parameters: [:]) else { return }
        
        var request = URLRequest(url: url)
        
        request.setValue("multipart/form-data", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        do {
            try request.setMultipartFormData(paramRequest, encoding: String.Encoding.utf8)
        } catch let error {
            print(NSError(domain: "Webasyst error(method: getAccessToken): \(error.localizedDescription)", code: 400, userInfo: nil))
        }
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    if let data = data {
                        do {
                            let authData = try JSONDecoder().decode(UserToken.self, from: data)
                            
                            let accessTokenData = Data("Bearer \(authData.access_token)".utf8)
                            let refreshTokenData = Data(authData.refresh_token.utf8)
                            
                            let accessTokenSuccess = KeychainManager.save(.accessToken, data: accessTokenData)
                            let refreshTokenSuccess = KeychainManager.save(.refreshToken, data: refreshTokenData)
                            
                            if accessTokenSuccess == 0 && refreshTokenSuccess == 0 {
                                completion(true)
                            } else {
                                completion(false)
                            }
                        } catch {
                            completion(false)
                            print(NSError(domain: "Webasyst error: decode error (getAccessToken) \n\(error).", code: 400, userInfo: nil))
                        }
                    }
                default:
                    completion(false)
                }
            }
        }.resume()
    }
    
    /// Token update method on the WAID server
    /// - Parameter completion: Short-circuiting after work methods
    /// - Returns: Returns the boolean value of token update success
    internal func refreshAccessToken(completion: @escaping (Bool) -> ()) {
        guard let config = WebasystApp.config else { return }
        
        let refreshToken = KeychainManager.getToken(.refreshToken)
        
        let paramsRequest: Parameters = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientId,
            "device_id": getDeviceId()
        ]
        
        guard let url = buildWebasystUrl("/id/oauth2/auth/token", parameters: [:]) else { return }
        
        var request = URLRequest(url: url)
        
        request.setValue("multipart/form-data", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        
        do {
            try request.setMultipartFormData(paramsRequest, encoding: String.Encoding.utf8)
        } catch let error {
            print(NSError(domain: "Webasyst error(method: refreshAccessToken): \(error.localizedDescription)", code: 400, userInfo: nil))
        }
        
        queue.async {
            URLSession.shared.dataTask(with: request) { (data, response, error) in
                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 200...299:
                        if let data = data {
                            do {
                                let authData = try JSONDecoder().decode(UserToken.self, from: data)
                                
                                let accessTokenData = Data("Bearer \(authData.access_token)".utf8)
                                let refreshTokenData = Data(authData.refresh_token.utf8)
                                
                                let accessTokenSuccess = KeychainManager.save(.accessToken, data: accessTokenData)
                                let refreshTokenSuccess = KeychainManager.save(.refreshToken, data: refreshTokenData)
                                
                                if accessTokenSuccess == 0 && refreshTokenSuccess == 0 {
                                    completion(true)
                                } else {
                                    completion(false)
                                }
                            } catch {
                                completion(false)
                                print(NSError(domain: "Webasyst error: decode error (refreshAccessToken) \n\(error).", code: 400, userInfo: nil))
                            }
                        }
                    default:
                        completion(false)
                    }
                }
            }.resume()
        }
    }
}
