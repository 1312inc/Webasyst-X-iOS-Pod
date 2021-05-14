//
//  WebasystNetworking.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 13.05.2021.
//

import Foundation
import CryptoKit

internal protocol WebasystNetworkingProtocol {
    func buildAuthRequest() -> URLRequest?
    func getAccessToken(_ authCode: String, stateString: String, completion: @escaping (Bool) -> Void)
}

internal typealias Parameters = [String: String]

internal struct UserToken: Codable {
    let access_token: String
    let token_type: String
    let expires_in: Int
    let refresh_token: String
}

internal class WebasystNetworking: WebasystNetworkingManager, WebasystNetworkingProtocol {
    
    private var config = WebasystApp.config
    private var disposablePasswordAuth: String?
    
    //MARK: Generating a one-time password in Webasyst
    private func generatePasswordHash(_ len: Int) -> String {
        let pswdChars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890")
        let rndPswd = String((0..<len).map{ _ in pswdChars[Int(arc4random_uniform(UInt32(pswdChars.count)))]})
        self.disposablePasswordAuth = rndPswd
        return rndPswd
    }
    
    //MARK: Build URLRequset in Webasyst Auth
    internal func buildAuthRequest() -> URLRequest? {
        
        guard let config = self.config else {
            print(NSError(domain: "WebasystApp not configuration", code: -1, userInfo: nil))
            return nil
        }
        
        let paramRequest: [String: String] = [
            "response_type": "code",
            "client_id": clientId,
            "scope": "token:blog.site.shop.webasyst",
            "redirect_uri": "\(config.bundleId)://oidc_callback",
            "state": config.bundleId,
            "code_challenge": "\(self.generatePasswordHash(64))",
            "code_challenge_method": "plain"
        ]
        
        var request = URLRequest(url: buildWebasystUrl("/id/oauth2/auth/code", parameters: paramRequest))
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
        
        let paramRequest: Parameters = [
            "grant_type": "authorization_code",
            "code": authCode,
            "redirect_uri": "\(String(describing: config?.bundleId ?? ""))://oidc_callback",
            "client_id": clientId,
            "code_verifier": disposablePassword
        ]
        
        let url = buildWebasystUrl("/id/oauth2/auth/token", parameters: [:])
        
        var request = URLRequest(url: url)
        
        request.setValue("multipart/form-data", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        try! request.setMultipartFormData(paramRequest, encoding: String.Encoding.utf8)
        
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
