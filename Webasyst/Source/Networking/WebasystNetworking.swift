//
//  WebasystNetworking.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 13.05.2021.
//

import Foundation

public typealias Parameters = [String: String]

internal class WebasystNetworking: WebasystNetworkingManager {
    
    private var config = WebasystApp.config
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
        
        guard let config = self.config else {
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
        
        guard let config = self.config else {
            print(NSError(domain: "Webasyst error(method: getAuthCode): Webasyst ID app Client Id is invalid. Please contact the app developer.", code: 400, userInfo: nil))
            success(AuthResult.undefined(error: "Webasyst ID app Client Id is invalid. Please contact the app developer."))
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
        case .phone:
            parametersRequest["phone"] = value
        case .email:
            parametersRequest["email"] = value
        }
        
        guard let url = self.buildWebasystUrl("/id/oauth2/auth/headless/code/", parameters: [:]) else {
            print(NSError(domain: "Webasyst error(method: getAuthCode): Authorisation URL generation error", code: 400, userInfo: nil))
            success(AuthResult.undefined(error: "Authorisation URL generation error"))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        do {
            try request.setMultipartFormData(parametersRequest, encoding: String.Encoding.utf8)
        } catch let error {
            print(NSError(domain: "Webasyst error(method: getAuthCode): \(error.localizedDescription)", code: 400, userInfo: nil))
            success(AuthResult.undefined(error: error.localizedDescription))
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil else {
                success(AuthResult.undefined(error: "Request error"))
                print(NSError(domain: "Webasyst error(method: getAuthCode): Request error", code: 400, userInfo: nil))
                return
            }
            
            guard let data = data else {
                success(AuthResult.undefined(error: "Error in receiving the server response body"))
                print(NSError(domain: "Webasyst error(method: getAuthCode): Error in receiving the server response body", code: 400, userInfo: nil))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                success(AuthResult.undefined(error: "Request error"))
                print(NSError(domain: "Webasyst error(method: getAuthCode): Request error", code: 400, userInfo: nil))
                return
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                success(AuthResult.success)
            case 400:
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if json["error"] as! String == "no_channels" {
                            success(AuthResult.no_channels)
                        } else if json["error"] as! String == "invalid_client" {
                            success(AuthResult.invalid_client)
                        } else if json["error"] as! String == "require_code_challenge" {
                            success(AuthResult.require_code_challenge)
                        } else if json["error"] as! String == "invalid_email" {
                            success(AuthResult.invalid_email)
                        } else if json["error"] as! String == "invalid_phone" {
                            success(AuthResult.invalid_phone)
                        } else {
                            if json["error"] != nil {
                                success(AuthResult.undefined(error: json["error"] as? String ?? ""))
                            } else {
                                success(AuthResult.undefined(error: "undefined server error"))
                            }
                        }
                    } else {
                        success(AuthResult.undefined(error: "Undefined error"))
                    }
                } catch let error {
                    success(AuthResult.undefined(error: error.localizedDescription))
                }
            case 408:
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if json["error"] as! String == "request_timeout_limit" {
                            success(AuthResult.request_timeout_limit)
                        } else {
                            if json["error"] != nil {
                                success(AuthResult.undefined(error: json["error"] as? String ?? ""))
                            } else {
                                success(AuthResult.undefined(error: "undefined server error"))
                            }
                        }
                    } else {
                        success(AuthResult.undefined(error: "Undefined error"))
                    }
                } catch let error {
                    success(AuthResult.undefined(error: error.localizedDescription))
                }
            case 500:
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if json["error"] as! String == "sent_notification_fail" {
                            success(AuthResult.sent_notification_fail)
                        } else if json["error"] as! String == "server_error" {
                            success(AuthResult.server_error)
                        } else {
                            if json["error"] != nil {
                                success(AuthResult.undefined(error: json["error"] as? String ?? ""))
                            } else {
                                success(AuthResult.undefined(error: "undefined server error"))
                            }
                        }
                    } else {
                        success(AuthResult.undefined(error: "Undefined error"))
                    }
                } catch let error {
                    success(AuthResult.undefined(error: error.localizedDescription))
                }
            default:
                success(AuthResult.server_error)
            }
        }.resume()
    }
    
    /// Authorization in Webasyst using Apple ID
    /// - Parameters:
    ///    - authData: Authorization data sent by the Apple ID authorization controller
    ///    - completion: success flag and optional error description
    internal func oAuthAppleID(authData: AuthAppleIDData, completion: @escaping (AppleIDResponse) -> ()) {
        
        guard let config = self.config else {
            let e = NSError(domain: "Webasyst error(method: oAuthAppleID): Webasyst ID app Client Id is invalid. Please contact the app developer.", code: 400, userInfo: nil)
            print(e)
            completion(.error(e.domain))
            return
        }
        
        var parametersRequest: Parameters = [
            "client_id": config.clientId,
            "device_id": getDeviceId(),
            "scope": "profile:write token:\(config.scope)",
            "user_identifier": authData.userIdentifier,
            "identity_token": authData.identityToken,
            "authorization_code": authData.authorizationCode,
            "email_verified": "\(authData.isRealUserStatus)"
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
        
        guard let url = buildWebasystUrl("/id/oauth2/auth/apple/", parameters: [:]) else { return }
        
        var request = URLRequest(url: url)
        
        request.setValue("multipart/form-data", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        do {
            try request.setMultipartFormData(parametersRequest, encoding: String.Encoding.utf8)
        } catch let error {
            print(NSError(domain: "Webasyst error(method: oAuthAppleID): \(error.localizedDescription)", code: 400, userInfo: nil))
        }
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            
            guard error == nil else {
                let e = NSError(domain: "Webasyst error(method: oAuthAppleID): Request error", code: 400, userInfo: nil)
                print(e)
                completion(.error(e.domain))
                return
            }
            
            guard let data = data else {
                let e = NSError(domain: "Webasyst error(method: oAuthAppleID): Error in receiving the server response body", code: 400, userInfo: nil)
                print(e)
                completion(.error(e.domain))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                let e = NSError(domain: "Webasyst error(method: oAuthAppleID): Request error", code: 400, userInfo: nil)
                print(e)
                completion(.error(e.domain))
                return
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                do {
                    let authData = try JSONDecoder().decode(UserToken.self, from: data)
                    let accessToken = Data("Bearer \(authData.access_token)".utf8)
                    if let emailConfirm = authData.email_confirm, emailConfirm == true {
                        completion(.success(.needEmailConfirmation(accessToken: accessToken)))
                    } else {
                        let accessTokenSuccess = KeychainManager.save(key: "accessToken", data: accessToken)
                        UserDefaults.standard.set(accessToken, forKey: "accessToken")
                        let refreshTokenSuccess = KeychainManager.save(key: "refreshToken", data: Data(authData.refresh_token.utf8))
                        if accessTokenSuccess == 0 && refreshTokenSuccess == 0 {
                            completion(.success(.succeess))
                        }
                    }
                } catch let error {
                    let e = NSError(domain: "Webasyst error(method: oAuthAppleID): \(error.localizedDescription)", code: 400, userInfo: nil)
                    print(e)
                    completion(.error(e.domain))
                }
            default:
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if json["error_description"] != nil {
                            let e = NSError(domain: "Webasyst error(method: oAuthAppleID): \(json["error_description"] as! String)", code: 400, userInfo: nil)
                            print(e)
                            completion(.error(e.domain))
                        } else if json["error"] != nil {
                            let e = NSError(domain: "Webasyst error(method: oAuthAppleID): \(json["error"] as! String)", code: 400, userInfo: nil)
                            print(e)
                            completion(.error(e.domain))
                        } else {
                            let e = NSError(domain: "Webasyst error(method: oAuthAppleID): undefined server error", code: 400, userInfo: nil)
                            print(e)
                            completion(.error(e.domain))
                        }
                    } else {
                        let e = NSError(domain: "Webasyst error(method: oAuthAppleID): undefined server error", code: 400, userInfo: nil)
                        print(e)
                        completion(.error(e.domain))
                    }
                } catch let error {
                    let e = NSError(domain: "Webasyst error(method: oAuthAppleID): \(error.localizedDescription)", code: 400, userInfo: nil)
                    print(e)
                    completion(.error(e.domain))
                }
            }
            
        }.resume()
    }
    
    /// Sending a confirmation code after calling the getAuthCode method or after reading qr-code
    /// - Parameters:
    ///   - type: Type of confirmation code
    ///   - code: Code received by user by e-mail or text message
    ///   - success: Closure performed after the method has been executed
    /// - Returns: Bool value whether the server has accepted the code, if true then the tokens are saved in the Keychain
    internal func sendConfirmCode(for type: AuthCodeType, _ code: String, success: @escaping (Bool) -> ()) {
        
        guard let config = self.config else {
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
                    let accessTokenSuccess = KeychainManager.save(key: "accessToken", data: Data("Bearer \(authData.access_token)".utf8))
                    UserDefaults.standard.set(Data("Bearer \(authData.access_token)".utf8), forKey: "accessToken")
                    let refreshTokenSuccess = KeychainManager.save(key: "refreshToken", data: Data(authData.refresh_token.utf8))
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
        guard let config = self.config else { return }
        
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
                        let authData = try! JSONDecoder().decode(UserToken.self, from: data)
                        let accessTokenSuccess = KeychainManager.save(key: "accessToken", data: Data("Bearer \(authData.access_token)".utf8))
                        UserDefaults.standard.set(Data("Bearer \(authData.access_token)".utf8), forKey: "accessToken")
                        let refreshTokenSuccess = KeychainManager.save(key: "refreshToken", data: Data(authData.refresh_token.utf8))
                        if accessTokenSuccess == 0 && refreshTokenSuccess == 0 {
                            completion(true)
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
    internal func refreshAccessToken(completion: @escaping (Bool)->()) {
        
        let refreshToken = KeychainManager.load(key: "refreshToken")
        let refreshTokenString = String(decoding: refreshToken ?? Data("".utf8), as: UTF8.self)
        guard let config = self.config else { return }
        
        let paramsRequest: Parameters = [
            "grant_type": "refresh_token",
            "refresh_token": refreshTokenString,
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
                            let authData = try! JSONDecoder().decode(UserToken.self, from: data)
                            KeychainManager.deleteAllKeys()
                            let accessTokenSuccess = KeychainManager.save(key: "accessToken", data: Data("Bearer \(authData.access_token)".utf8))
                            UserDefaults.standard.set(Data("Bearer \(authData.access_token)".utf8), forKey: "accessToken")
                            let refreshTokenSuccess = KeychainManager.save(key: "refreshToken", data: Data(authData.refresh_token.utf8))
                            if accessTokenSuccess == 0 && refreshTokenSuccess == 0 {
                                completion(true)
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
