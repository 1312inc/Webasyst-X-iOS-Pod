//
//  WebasystUserNetworking.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 17.05.2021.
//

import Foundation

public struct UserData: Codable {
    public let name: String
    public let firstname: String
    public let lastname: String
    public let middlename: String
    public let email: [Email]
    public let userpic_original_crop: String
}

public struct Email: Codable {
    public let value: String
}

internal struct InstallInfo: Decodable {
    var name: String
    var logo: Logo?
}

internal struct Logo: Decodable {
    var mode: ImageType
}

enum ImageType: Decodable {
    case image, gradient
    case unknown(value: String)
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let status = try? container.decode(String.self)
        switch status {
        case "image": self = .image
        case "gradient": self = .gradient
        default:
            self = .unknown(value: status ?? "unknown")
        }
    }
}

struct LogoGradient: Codable {
    var name: String
    var logo: Gradient?
}

struct Gradient: Codable {
    var gradient: GradientType
}

struct GradientType: Codable {
    var from: String
    var to: String
    var angle: String
}

struct LogoImage: Codable {
    var name: String
    var logo: TypeImage?
}

struct TypeImage: Codable {
    var image: Original
}

struct Original: Codable {
    var original: OriginalImage
}

struct OriginalImage: Codable {
    var url: String
}

final class WebasystUserNetworking: WebasystNetworkingManager {
    
    private let bundleId: String = WebasystApp.config?.bundleId ?? ""
    private let profileInstallService = WebasystDataModel()
    private let webasystNetworkingService = WebasystNetworking()
    private let networkingHelper = NetworkingHelper()
    private let queue = DispatchQueue(label: "com.webasyst.x.ios.WebasystUserNetworkingService", qos: .userInitiated)
    private let dispatchGroup = DispatchGroup()
    private let config = WebasystApp.config
    
    func preloadUserData(completion: @escaping (String, Int, Bool) -> ()) {
        if self.networkingHelper.isConnectedToNetwork() {
            self.queue.async(group: self.dispatchGroup) {
                self.webasystNetworkingService.refreshAccessToken { result in
                    if result {
                        print("Webasyst refresh token is success")
                    } else {
                        print("Webasyst refresh token is error")
                    }
                }
            }
            self.queue.async {
                self.downloadUserData()
            }
            self.dispatchGroup.notify(queue: self.queue) {
                self.getInstallList { installList in
                    guard let installs = installList else {
                        completion(NSLocalizedString("loadingError", comment: ""), 30, true)
                        return
                    }
                    var clientId: [String] = []
                    for install in installs {
                        clientId.append(install.id)
                    }
                    self.getAccessTokenApi(clientId: clientId) { (success, accessToken) in
                        if success {
                            guard let token = accessToken else {
                                completion("Webasyst Error: get access token error", 30, false)
                                return
                            }
                            self.getAccessTokenInstall(installs, accessCodes: token) { (loadText, saveSuccess) in
                                if !saveSuccess {
                                    completion(loadText, 30, true)
                                } else {
                                    completion(loadText, 100, true)
                                }
                            }
                        } else {
                            print("Webasyst error: error in obtaining installation tokens")
                        }
                    }
                    if installList != nil {
                        
                    } else {
                        completion(NSLocalizedString("loadingError", comment: ""), 30, true)
                    }
                }
            }
        } else {
            completion(NSLocalizedString("connectionAlertMessage", comment: ""), 0, false)
        }
    }
    
    //MARK: Download user data
    internal func downloadUserData() {
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let headers: [String: String] = [
            "Authorization": accessTokenString
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/profile/", parameters: [:]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    if let data = data {
                        let userData = try! JSONDecoder().decode(UserData.self, from: data)
                        WebasystNetworkingManager().downloadImage(userData.userpic_original_crop) { data in
                            WebasystDataModel()?.saveProfileData(userData, avatar: data)
                        }
                    }
                default:
                    print(httpResponse.statusCode)
                }
            }
        }.resume()
    }
    
    //MARK: Get installation's list user
    public func getInstallList(completion: @escaping ([UserInstall]?) -> ()) {
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let headers: [String: String] = [
            "Authorization": accessTokenString
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/installations/", parameters: [:]) else {
            print("Webasyst error: Failed to retrieve list of user settings")
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    if let data = data {
                        let installList = try! JSONDecoder().decode([UserInstall].self, from: data)
                        completion(installList)
                    }
                default:
                    completion(nil)
                    print(httpResponse.statusCode)
                }
            }
        }.resume()
        
    }
    
    func getAccessTokenApi(clientId: [String], completion: @escaping (Bool, [String: Any]?) -> ()) {
        
        let paramReqestApi: Dictionary<String, Any> = [
            "client_id": clientId
        ]
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        guard let url = buildWebasystUrl("/id/api/v1/auth/client/", parameters: [:]) else {
            completion(false, [:])
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(accessTokenString, forHTTPHeaderField: "Authorization")
        
        do {
            let data = try JSONSerialization.data(withJSONObject: paramReqestApi) as Data
            request.addValue("\(data.count)", forHTTPHeaderField: "Content-Length")
            request.httpBody = data
        } catch let error {
            print("Webasyst error: \(error.localizedDescription)")
        }
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard error == nil else {
                return
            }
            
            guard let data = data else {
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    completion(true, json)
                }
            } catch let error {
                print("Webasyst error: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    func getAccessTokenInstall(_ installList: [UserInstall], accessCodes: [String: Any], completion: @escaping (String, Bool) -> ()) {
        
        guard let config = WebasystApp.config else { return }
        
        for install in installList {
            
            let code = accessCodes[install.id] as! String
            
            let parameters: [String: String] = [
                "code" : code,
                "scope": config.scope,
                "client_id": config.bundleId
            ]
            
            guard let url = URL(string: "\(String(describing: install.url))/api.php/token-headless") else {
                print("Webasyst error: Url install error")
                break
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            do {
                try request.setMultipartFormData(parameters, encoding: String.Encoding.utf8)
            } catch {
                print("Webasyst error: Failed to get request body")
            }
            
            
            URLSession.shared.dataTask(with: request) { (data, response, error) in
                guard error == nil else {
                    return
                }
                
                guard let data = data else {
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
                        let installToken = UserInstall(name: "", domain: install.domain, id: install.id, accessToken: json["access_token"]  ?? "", url: install.url)
                        self.getInstallInfo(installToken)
                        completion("\(NSLocalizedString("loadingInstallMessage", comment: "")) \(install.domain)", false)
                    }
                } catch let error {
                    print("Webasyst error: Domain: \(install.url) \(error.localizedDescription)")
                }
            }.resume()
        }
    }
    
    func getInstallInfo(_ install: UserInstall) {
        
        guard let url = URL(string: "\(install.url)/api.php/webasyst.getInfo?access_token=\(install.accessToken ?? "")&format=json") else {
            print("Webasyst error: Failed to generate a url when getting installation information")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil else {
                return
            }
            
            guard let data = data else {
                return
            }
            
            do {
                let info = try JSONDecoder().decode(InstallInfo.self, from: data)
                guard let logoMode = info.logo else {
                    let newInstall = UserInstall(name: info.name, domain: install.domain , id: install.id , accessToken: install.accessToken, url: install.url)
                    self.profileInstallService?.saveInstall(newInstall, accessToken: install.accessToken ?? "", image:  nil)
                    return
                }
                switch logoMode.mode {
                case .image:
                    do {
                        let imageInfo = try JSONDecoder().decode(LogoImage.self, from: data)
                        self.downloadImage(imageInfo.logo?.image.original.url ?? "") { imageData in
                            let saveInstall = UserInstall(name: info.name, domain: install.domain, id: install.id, accessToken: install.accessToken, url: install.url, image: nil)
                            self.profileInstallService?.saveInstall(saveInstall, accessToken: install.accessToken ?? "", image: imageData)
                        }
                    } catch let error {
                        print("Webasyst error: \(info.name) \(error.localizedDescription)")
                    }
                case .gradient:
                    do {
                        let imageInfo = try JSONDecoder().decode(LogoGradient.self, from: data)
                        print("graient", imageInfo.logo?.gradient as Any)
                    } catch let error {
                        print("Webasyst error: \(info.name) \(error.localizedDescription)")
                    }
                case .unknown(value: _):
                    let newInstall = UserInstall(name: info.name, domain: install.domain , id: install.id , accessToken: install.accessToken, url: install.url)
                    self.profileInstallService?.saveInstall(newInstall, accessToken: install.accessToken ?? "", image:  nil)
                }
            } catch let error {
                let newInstall = UserInstall(name: install.domain, domain: install.domain , id: install.id , accessToken: install.accessToken, url: install.url)
                self.profileInstallService?.saveInstall(newInstall, accessToken: install.accessToken ?? "", image: nil)
                print("Webasyst error: \(install.url) \(error.localizedDescription)")
            }
        }.resume()
        
    }
    
    func singUpUser(completion: @escaping (Bool) -> ()) {
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let headerRequest: [String: String] = [
            "Authorization": accessTokenString
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/delete/", parameters: [:]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(headerRequest.first?.value ?? "", forHTTPHeaderField: headerRequest.first?.key ?? "")
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    completion(true)
                default:
                    print("singUpUser status code request \(httpResponse.statusCode)")
                    completion(false)
                }
            }
        }
    }
}
