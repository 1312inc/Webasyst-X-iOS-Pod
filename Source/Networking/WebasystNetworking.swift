//
//  WebasystNetworking.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 13.05.2021.
//

import Foundation

internal typealias Parameters = [String: String]

internal class WebasystNetworking: WebasystNetworkingManager {
    
    private var config = WebasystApp.config
    private var disposablePasswordAuth: String?
    
    /// Generating a temporary password for user authentication
    /// - Parameter len: Length of the required password
    /// - Returns: Returns the password in string representation
    private func generatePasswordHash(_ len: Int) -> String {
        let pswdChars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890")
        let rndPswd = String((0..<len).map{ _ in pswdChars[Int(arc4random_uniform(UInt32(pswdChars.count)))]})
        self.disposablePasswordAuth = rndPswd
        return rndPswd
    }
    
    /// Building a request for user authorization
    /// - Returns: Returns authorization request
    internal func buildAuthRequest() -> URLRequest? {
        
        guard let config = self.config else {
            print(NSError(domain: "WebasystApp not configuration", code: -1, userInfo: nil))
            return nil
        }
        
        let paramRequest: Parameters = [
            "response_type": "code",
            "client_id": config.clientId,
            "scope": "token:blog.site.shop.webasyst",
            "redirect_uri": "\(config.bundleId)://oidc_callback",
            "state": config.bundleId,
            "code_challenge": "\(self.generatePasswordHash(64))",
            "code_challenge_method": "plain"
        ]
        
        guard let urlRequest = buildWebasystUrl("/id/oauth2/auth/code", parameters: paramRequest) else { return nil }
 
        var request = URLRequest(url: urlRequest)
        request.httpMethod = "GET"
        return request
    }
    
    /// Getting a permanent Webasyst token
    /// - Parameters:
    ///   - authCode: OAuth code from the server
    ///   - stateString: state value from the server
    ///   - completion: Result of a request to the server
    func getAccessToken(_ authCode: String, stateString: String, completion: @escaping (Bool) -> Void) {
        
        guard let disposablePassword = self.disposablePasswordAuth else { return }
        guard let config = self.config else { return }
        
        let paramRequest: Parameters = [
            "grant_type": "authorization_code",
            "code": authCode,
            "redirect_uri": "\(String(describing: config.bundleId))://oidc_callback",
            "client_id": config.clientId,
            "code_verifier": disposablePassword
        ]
        
        guard let url = buildWebasystUrl("/id/oauth2/auth/token", parameters: [:]) else { return }
        
        var request = URLRequest(url: url)
        
        request.setValue("multipart/form-data", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        do {
            try request.setMultipartFormData(paramRequest, encoding: String.Encoding.utf8)
        } catch let error {
            print("Webasyst error: \(error.localizedDescription)")
        }
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    if let data = data {
                        let authData = try! JSONDecoder().decode(UserToken.self, from: data)
                        let accessTokenSuccess = KeychainManager.save(key: "accessToken", data: Data("Bearer \(authData.access_token)".utf8))
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
            "client_id": config.clientId
        ]
        
        guard let url = buildWebasystUrl("/id/oauth2/auth/token", parameters: [:]) else { return }
        
        var request = URLRequest(url: url)
        
        request.setValue("multipart/form-data", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        
        do {
            try request.setMultipartFormData(paramsRequest, encoding: String.Encoding.utf8)
        } catch let error {
            print("Webasyst error: \(error.localizedDescription)")
        }
        
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    if let data = data {
                        let authData = try! JSONDecoder().decode(UserToken.self, from: data)
                        let accessTokenSuccess = KeychainManager.save(key: "accessToken", data: Data("Bearer \(authData.access_token)".utf8))
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
