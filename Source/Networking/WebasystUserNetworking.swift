//
//  WebasystUserNetworking.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 17.05.2021.
//

import Foundation

public enum Result {
    case success
    case failure(Error)
}

final class WebasystUserNetworking: WebasystNetworkingManager {
    
    private let profileInstallService = WebasystDataModel()
    private let webasystNetworkingService = WebasystNetworking()
    private let networkingHelper = NetworkingHelper()
    private let config = WebasystApp.config
    private let demoToken = "5f9db4d32d9a586c2daca4b45de23eb8"
    private lazy var queue = DispatchQueue(label: "\(config?.bundleId ?? "com.webasyst.x").WebasystUserNetworkingService", qos: .userInitiated)
    private let defaultImageUrl = "https://www.webasyst.com/wa-content/img/userpic96.jpg"
    
    func preloadUserData(completion: @escaping (UserStatus, Int, Bool) -> ()) {
        if self.networkingHelper.isConnectedToNetwork() {
            queue.async { [weak self] in
                self?.downloadUserData { condition in
                    self?.getInstallList { installList in
                        guard let installs = installList else { return }
                        var clientId: [String] = []
                        for install in installs {
                            clientId.append(install.id)
                        }
                        self?.getAccessTokenApi(clientId: clientId) { (success, accessToken) in
                            if success {
                                guard let token = accessToken else { return }
                                self?.getAccessTokenInstall(installs, accessCodes: token) { (loadText, saveSuccess) in
                                    UserDefaults.standard.setValue(false, forKey: "firstLaunch")
                                    if installs.isEmpty || condition {
                                        if condition && !installs.isEmpty {
                                            completion(.authorizedButProfileIsEmpty, 30, true)
                                        } else if !condition && installs.isEmpty {
                                            completion(.authorizedButNoneInstalls, 30, true)
                                        } else if condition && installs.isEmpty {
                                            completion(.authorizedButNoneInstallsAndProfileIsEmpty, 30, true)
                                        }
                                    } else {
                                        completion(.authorized, 30, saveSuccess)
                                    }
                                }
                            } else {
                                if !condition && installs.isEmpty {
                                    completion(.authorizedButNoneInstalls, 30, true)
                                } else if condition && installs.isEmpty {
                                    completion(.authorizedButNoneInstallsAndProfileIsEmpty, 30, true)
                                }
                            }
                        }
                    }
                }
            }
        } else {
            completion(.networkError(NSLocalizedString("connectionAlertMessage", comment: "")), 0, false)
        }
    }
    
    // MARK: - Send Apple ID email confirmation code
    internal func sendAppleIDEmailConfirmationCode(_ code: String, accessToken: Data, success: @escaping (Bool, String?) -> ()) {
        
        let accessTokenString = String(decoding: accessToken, as: UTF8.self)
        
        let headers: Parameters = [
            "Authorization": accessTokenString
        ]
        
        let parametersRequest: Parameters = [
            "code": code
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/apple/confirm/", parameters: [:]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        if let encodedData = try? JSONSerialization.data(withJSONObject: parametersRequest,
                                                         options: .fragmentsAllowed) {
            request.httpBody = encodedData
        }
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            
            guard error == nil else {
                let e = "Webasyst error(method: sendAppleIDEmailConfirmationCode): Request error. \(error!.localizedDescription)"
                print(NSError(domain: e, code: 400, userInfo: nil))
                success(false, e)
                return
            }
            
            guard let data = data else {
                let e = "Webasyst error(method: sendAppleIDEmailConfirmationCode): Error in receiving the server response body"
                print(NSError(domain: e, code: 400, userInfo: nil))
                success(false, e)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                let e = "Webasyst error(method: sendAppleIDEmailConfirmationCode): Request error"
                print(NSError(domain: e, code: 400, userInfo: nil))
                success(false, e)
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
                        success(true, nil)
                    }
                } catch let error {
                    let e = "Webasyst error(method: sendAppleIDEmailConfirmationCode): \(error.localizedDescription)"
                    success(false, e)
                    print(NSError(domain: e, code: 400, userInfo: nil))
                }
            default:
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if json["error_description"] != nil {
                            let e = "Webasyst error(method: sendAppleIDEmailConfirmationCode): \(json["error_description"] as! String)"
                            success(false, e)
                            print(NSError(domain: e, code: 400, userInfo: nil))
                        } else if json["error"] != nil {
                            let e = "Webasyst error(method: sendAppleIDEmailConfirmationCode): \(json["error"] as! String)"
                            success(false, e)
                            print(NSError(domain: e, code: 400, userInfo: nil))
                        } else {
                            let e = "Webasyst error(method: sendAppleIDEmailConfirmationCode): undefined server error"
                            success(false, e)
                            print(NSError(domain: "Webasyst error(method: sendAppleIDEmailConfirmationCode): undefined server error", code: 400, userInfo: nil))
                        }
                    } else {
                        let e = "Webasyst error(method: sendAppleIDEmailConfirmationCode): undefined server error"
                        success(false, e)
                        print(NSError(domain: "Webasyst error(method: sendAppleIDEmailConfirmationCode): undefined server error", code: 400, userInfo: nil))
                    }
                } catch let error {
                    let e = "Webasyst error(method: sendAppleIDEmailConfirmationCode): \(error.localizedDescription)"
                    success(false, e)
                    print(NSError(domain: "Webasyst error(method: sendAppleIDEmailConfirmationCode): \(error.localizedDescription)", code: 400, userInfo: nil))
                }
            }
            
        }.resume()
    }
    
    //MARK: Download user data
    internal func downloadUserData(_ completion: @escaping (Bool) -> Void) {
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let headers: Parameters = [
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
                        let condition = userData.firstname.isEmpty || userData.lastname.isEmpty
                        completion(condition)
                        WebasystNetworkingManager().downloadImage(userData.userpic_original_crop) { [weak self] data in
                            self?.profileInstallService?.saveProfileData(userData, avatar: data)
                        }
                    }
                default:
                    print(NSError(domain: "Webasyst error: user data upload error", code: 400, userInfo: nil))
                }
            }
        }.resume()
    }
    
    public func changeUserData(_ profile: ProfileData,_ completion: @escaping (Swift.Result<ProfileData,Error>) -> Void) {
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        var parameters: Dictionary<String,Any> = [
            "firstname": profile.firstname,
            "lastname": profile.lastname,
            "middlename" : profile.middlename
        ]
        
        if !profile.email.isEmpty {
            parameters["email"] = [profile.email]
        }
        if !profile.phone.isEmpty {
            parameters["phone"] = [profile.phone]
        }
        
        let headers: Parameters = [
            "Accept" : "application/json",
            "Authorization" : accessTokenString,
            "Content-Type" : "application/json"
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/profile", parameters: [:]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpBody = try! JSONSerialization.data(withJSONObject: parameters, options: .fragmentsAllowed)
        
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    if let data = data, let userData = try? JSONDecoder().decode(UserData.self, from: data) {
                        WebasystNetworkingManager().downloadImage(userData.userpic_original_crop) { [weak self] data in
                            self?.profileInstallService?.saveProfileData(userData, avatar: data)
                            completion(.success(profile))
                        }
                    }
                default:
                    let error: Error
                    if let data = data,
                       let dictionary = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String:Any],
                       let errorDescription = dictionary?["error_description"] as? String {
                        error = NSError(domain: "Webasyst error: \(errorDescription)", code: httpResponse.statusCode, userInfo: nil)
                    } else {
                        error = NSError(domain: "Webasyst error: user data upload error", code: httpResponse.statusCode, userInfo: nil)
                    }
                    completion(.failure(error))
                    print(error)
                }
            }
        }.resume()
    }
    
    public func deleteUserAvatar(_ completion: @escaping (Result) -> Void) {
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let headers: Parameters = [
            "Authorization": accessTokenString
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/profile/userpic/", parameters: [:]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 204:
                    WebasystNetworkingManager().downloadImage(self.defaultImageUrl) { [weak self] data in
                        self?.profileInstallService?.saveNewAvatar(data)
                        completion(.success)
                    }
                default:
                    let error = NSError(domain: "Webasyst error: user data upload error", code: 400, userInfo: nil)
                    completion(.failure(error))
                    print(error)
                }
            }
        }.resume()
    }
    
    public func updateUserAvatar(_ image: UIImage, _ completion: @escaping (Result) -> Void) {
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        guard let url = buildWebasystUrl("/id/api/v1/profile/userpic", parameters: [:]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let imageData = UIImageJPEGRepresentation(image, 1)!
        
        let headers: Parameters = [
            "Authorization": accessTokenString,
            "Content-Type": "image/jpeg"
        ]
        
        request.httpBody = imageData
        
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 201:
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String:Any],
                       let original_image = json?["userpic_original_crop"] as? String {
                        WebasystNetworkingManager().downloadImage(original_image) { [weak self] data in
                            self?.profileInstallService?.saveNewAvatar(data)
                            completion(.success)
                        }
                    } else {
                        let str = "Error code is \(httpResponse.statusCode.description)"
                        let error = NSError(domain: str, code: httpResponse.statusCode, userInfo: nil)
                        completion(.failure(error))
                    }
                default:
                    let str = "Error code is \(httpResponse.statusCode.description)"
                    let error = NSError(domain: str, code: httpResponse.statusCode, userInfo: nil)
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    //MARK: Get installation's list user
    public func getInstallList(completion: @escaping ([UserInstallCodable]?) -> ()) {
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let headers: Parameters = [
            "Authorization": accessTokenString
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/installations/", parameters: [:]) else {
            print(NSError(domain: "Webasyst error: Failed to retrieve list of user settings", code: 400, userInfo: nil))
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    if let data = data {
                        let installList = try! JSONDecoder().decode([UserInstallCodable].self, from: data)
                        let activeInstall = UserDefaults.standard.string(forKey: "selectDomainUser") ?? ""
                        if let install = installList.first?.id, activeInstall.isEmpty || !installList.contains(where: { $0.id == activeInstall }) {
                            UserDefaults.standard.setValue(install, forKey: "selectDomainUser")
                        }
                        completion(installList)
                        self?.deleteNonActiveInstall(installList: installList)
                    }
                default:
                    completion(nil)
                    print(NSError(domain: "Webasyst error: Failed to retrieve list of user settings", code: 400, userInfo: nil))
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
        } catch {
            print(NSError(domain: "Webasyst error: \(error.localizedDescription)", code: 400, userInfo: nil))
        }
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            do {
                if error == nil,
                   let data = data,
                   let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    completion(true, json)
                } else {
                    completion(false,[:])
                }
            } catch let error {
                print(NSError(domain: "Webasyst error: \(error.localizedDescription)", code: 400, userInfo: nil))
            }
        }.resume()
    }
    
    func getAccessTokenInstall(_ installList: [UserInstallCodable], accessCodes: [String: Any], completion: @escaping (String, Bool) -> ()) {
        
        guard let config = WebasystApp.config else { return }
        if let error = accessCodes["error_description"] as? String {
            print(NSError(domain: "Webasyst error: Access codes not founded (\(error)", code: 401))
            return
        }
        
        for index in 0..<installList.count {
            let code = accessCodes[installList[index].id] as! String
            
            let replaceScope = config.scope
            
            let parameters: Parameters = [
                "code" : code,
                "scope": String(replaceScope.map {
                    $0 == "." ? "," : $0
                }),
                "client_id": config.bundleId
            ]
            
            guard let url = URL(string: "\(String(describing: installList[index].url))/api.php/token-headless") else {
                print(NSError(domain: "Webasyst error: Url install error", code: 401, userInfo: nil))
                break
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            do {
                try request.setMultipartFormData(parameters, encoding: String.Encoding.utf8)
            } catch let error {
                print(NSError(domain: "Webasyst error: \(error.localizedDescription)", code: 401, userInfo: nil))
            }
            
            URLSession.shared.dataTask(with: request) { [weak self] (data, response, error) in
                guard error == nil, let data = data else {
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? Parameters {
                        let installToken = UserInstallCodable(name: "", domain: installList[index].domain, id: installList[index].id, accessToken: json["access_token"] ?? "", url: installList[index].url, cloudPlanId: installList[index].cloudPlanId, cloudExpireDate: installList[index].cloudExpireDate, cloudTrial: installList[index].cloudTrial)
                        self?.getInstallInfo(installToken) { install in
                            if index == 0 {
                                completion(json["access_token"] ?? "", true)
                            }
                        }
                    }
                } catch let error {
                    print(NSError(domain: "Webasyst error: Domain: \(installList[index].url) \(error.localizedDescription)", code: 401, userInfo: nil))
                }
            }.resume()
        }
    }
    
    func getInstallInfo(_ install: UserInstallCodable, loadSucces: @escaping (Bool) -> ()) {
        
        guard let url = URL(string: "\(install.url)/api.php/webasyst.getInfo?access_token=\(install.accessToken ?? "")&format=json") else {
            print(NSError(domain: "Webasyst error: Failed to generate a url when getting installation information", code: 401, userInfo: nil))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            guard error == nil, let data = data else {
                return
            }
            do {
                let info = try JSONDecoder().decode(InstallInfo.self, from: data)
                guard let logoMode = info.logo else {
                    let imageData = self.createDefaultGradient()
                    let newInstall = UserInstall(name: info.name, domain: install.domain , id: install.id , accessToken: install.accessToken, url: install.url, image: imageData, imageLogo: false, logoText: info.logo?.text.value ?? "", logoTextColor: info.logo?.text.color ?? "", cloudPlanId: install.cloudPlanId, cloudExpireDate: install.cloudExpireDate, cloudTrial: install.cloudTrial)
                    self.profileInstallService?.saveInstall(newInstall)
                    self.profileInstallService?.createNew()
                    loadSucces(true)
                    return
                }
                switch logoMode.mode {
                case .image:
                    do {
                        let imageInfo = try JSONDecoder().decode(LogoImage.self, from: data)
                        self.downloadImage(imageInfo.logo?.image.thumbs.first?.value.url ?? "") { imageData in
                            let saveInstall = UserInstall(name: info.name, domain: install.domain, id: install.id, accessToken: install.accessToken, url: install.url, image: imageData, imageLogo: true, logoText: "", logoTextColor: "", cloudPlanId: install.cloudPlanId, cloudExpireDate: install.cloudExpireDate, cloudTrial: install.cloudTrial)
                            self.profileInstallService?.saveInstall(saveInstall)
                            self.profileInstallService?.createNew()
                            loadSucces(true)
                        }
                    } catch let error {
                        print(NSError(domain: "Webasyst error: \(info.name) \(error.localizedDescription)", code: 401, userInfo: nil))
                    }
                case .gradient:
                    do {
                        let imageInfo = try JSONDecoder().decode(LogoGradient.self, from: data)
                        
                        let imageData = self.createGradient(from: imageInfo.logo?.gradient.from ?? "#FF0078", to: imageInfo.logo?.gradient.to ?? "#FF5900")
                        let install = UserInstall(name: info.name, domain: install.domain, id: install.id, accessToken: install.accessToken, url: install.url, image: imageData, imageLogo: false, logoText: info.logo?.text.value ?? "", logoTextColor: info.logo?.text.color ?? "", cloudPlanId: install.cloudPlanId, cloudExpireDate: install.cloudExpireDate, cloudTrial: install.cloudTrial)
                        
                        self.profileInstallService?.saveInstall(install)
                        self.profileInstallService?.createNew()
                        loadSucces(true)
                    } catch let error {
                        print(NSError(domain: "Webasyst error: \(info.name) \(error.localizedDescription)", code: 401, userInfo: nil))
                    }
                case .unknown(value: _):
                    let imageData = self.createDefaultGradient()
                    
                    let newInstall = UserInstall(name: info.name, domain: install.domain , id: install.id , accessToken: install.accessToken, url: install.url, image: imageData, imageLogo: false, logoText: info.logo?.text.value ?? "", logoTextColor: info.logo?.text.color ?? "", cloudPlanId: install.cloudPlanId, cloudExpireDate: install.cloudExpireDate, cloudTrial: install.cloudTrial)
                    
                    self.profileInstallService?.saveInstall(newInstall)
                    self.profileInstallService?.createNew()
                    loadSucces(true)
                }
            } catch let error {
                let imageData = self.createDefaultGradient()
                let newInstall = UserInstall(name: install.domain, domain: install.domain , id: install.id , accessToken: install.accessToken, url: install.url, image: imageData, imageLogo: false, logoText: "", logoTextColor: "", cloudPlanId: install.cloudPlanId, cloudExpireDate: install.cloudExpireDate, cloudTrial: install.cloudTrial)
                
                self.profileInstallService?.saveInstall(newInstall)
                loadSucces(true)
                print(NSError(domain: "Webasyst warning: \(install.url) \(error.localizedDescription)", code: 205, userInfo: nil))
            }
        }.resume()
        
    }
    
    func createWebasystAccount(bundle: String, plainId: String, accountName: String?, completion: @escaping (Bool, String?, String?)->()) {
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let headers: Parameters = [
            "Authorization": accessTokenString
        ]
        
        var parametersRequest: Parameters = [
            "bundle": bundle,
            "plan_id": plainId
        ]
        
        if let accountName = accountName {
            parametersRequest["account_name"] = accountName
        }
        
        guard let url = buildWebasystUrl("/id/api/v1/cloud/signup/", parameters: [:]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        if let encodedData = try? JSONSerialization.data(withJSONObject: parametersRequest,
                                                         options: .fragmentsAllowed) {
            request.httpBody = encodedData
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] (data, response, error) in
            guard error == nil, let data = data else {
                print(NSError(domain: "Webasyst error: \(String(describing: error?.localizedDescription))", code: 401, userInfo: nil))
                completion(false, nil, nil)
                return
            }
            do {
                if let dictionary = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String:Any] {
                    if let id = dictionary["id"] as? String,
                       let url = dictionary["url"] as? String,
                       let domain = dictionary["domain"] as? String {
                        var newInstall: [UserInstallCodable] = []
                        self?.getAccessTokenApi(clientId: [id]) { success, accessCode in
                            if success {
                                newInstall.append(UserInstallCodable(name: nil,
                                                                     domain: domain,
                                                                     id: id,
                                                                     accessToken: nil,
                                                                     url: url,
                                                                     image: nil))
                                self?.getAccessTokenInstall(newInstall, accessCodes: accessCode ?? [:]) { token, success in
                                    completion(true, id, url)
                                }
                            } else {
                                let e = "Webasyst error: The account was successfully created, but it was not possible to get an access token for it."
                                print(e)
                                completion(false, nil, e)
                            }
                        }
                    } else  {
                        if let error = dictionary["error_description"] as? String, !error.isEmpty {
                            completion(false, nil, error)
                        } else if let error = dictionary["error"] as? String, !error.isEmpty {
                            completion(false, nil, error)
                        } else {
                            completion(false, nil, nil)
                        }
                    }
                }
            } catch {
                if let dictionary = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String:Any] {
                    if let error = dictionary?["error_description"] as? String, !error.isEmpty {
                        completion(false, nil, error)
                    } else if let error = dictionary?["error"] as? String, !error.isEmpty {
                        completion(false, nil, error)
                    } else {
                        completion(false, nil, nil)
                    }
                } else {
                    completion(false, nil, nil)
                }
            }
            
        }.resume()
    }
    
    func renameWebasystAccount(clientId: String, domain: String, completion: @escaping (Result) -> ()) {
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let headers: Parameters = [
            "Authorization": accessTokenString
        ]
        
        let parametersRequest: Parameters = [
            "client_id": clientId,
            "domain": domain
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/cloud/rename/", parameters: [:]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        if let encodedData = try? JSONSerialization.data(withJSONObject: parametersRequest,
                                                         options: .fragmentsAllowed) {
            request.httpBody = encodedData
        }
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard error == nil, let data = data else {
                let e = NSError(domain: "Webasyst error: \(String(describing: error?.localizedDescription))", code: 401, userInfo: nil)
                print(e)
                completion(.failure(e))
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 204:
                    completion(.success)
                default:
                    var errorDescription: String
                    if let dictionary = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String:Any] {
                        if let error = dictionary?["error_description"] as? String, !error.isEmpty {
                            errorDescription = error
                        } else if let error = dictionary?["error"] as? String, !error.isEmpty {
                            errorDescription = error
                        } else {
                            errorDescription = "Webasyst warning: renameWebasystAccount status code request \(httpResponse.statusCode)"
                        }
                    } else {
                        errorDescription = "Webasyst warning: renameWebasystAccount status code request \(httpResponse.statusCode)"
                    }
                    let e = NSError(domain: errorDescription, code: httpResponse.statusCode, userInfo: nil)
                    print(e)
                    completion(.failure(e))
                }
            } else {
                let e = NSError(domain: "Webasyst error: invalid response from the server", code: 401, userInfo: nil)
                print(e)
                completion(.failure(e))
            }
        }.resume()
    }
    
    func singUpUser(completion: @escaping (Bool) -> ()) {
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let headerRequest: Parameters = [
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
                    print(NSError(domain: "Webasyst warning: singUpUser status code request \(httpResponse.statusCode)", code: 205, userInfo: nil))
                    completion(false)
                }
            }
        }.resume()
    }
    
    func checkAppInstall(app: String, completion: @escaping (Swift.Result<String?, String>) -> Void) {
        
        guard let domain = UserDefaults.standard.string(forKey: "selectDomainUser"),
              let install = profileInstallService?.getInstall(with: domain),
              let accessToken = install.accessToken,
              let url = URL(string: "\(install.url)/api.php/installer.product.install") else { return }
        
        let parameters: Parameters = [
            "Authorization": accessToken
        ]
        
        let data = "slug=\(app)".data(using: .utf8)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        
        for (key, value) in parameters {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            if let data = data,
               let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
               let _ = object as? Bool {
                completion(.success(nil))
            } else if let data = data, let dictionary = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String:Any] {
                if let error = dictionary?["error_description"] as? String {
                    completion(.failure(error))
                } else if let error = dictionary?["error"] as? String {
                    completion(.failure(error))
                }
            }
        }).resume()
        
    }
    
    func checkInstallLicense(app: String, completion: @escaping (Swift.Result<String?, String>) -> Void) {
        
        guard let domain = UserDefaults.standard.string(forKey: "selectDomainUser"),
              let url = buildWebasystUrl("/id/api/v1/licenses/force/", parameters: [:]) else { return }
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let parameters: Parameters = [
            "Authorization": accessTokenString
        ]
        let json = ["client_id": domain,
                    "slug":app]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let data = try JSONEncoder().encode(json) as Data
            request.addValue("\(data.count)", forHTTPHeaderField: "Content-Length")
            request.httpBody = data
        } catch {
            print(NSError(domain: "Webasyst error: \(error.localizedDescription)", code: 400, userInfo: nil))
        }
        
        for (key, value) in parameters {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse else { return }
            if httpResponse.statusCode == 204 {
                completion(.success(nil))
            } else if let data = data, var error = String(data: data, encoding: .utf8) {
                error += " \n Error code is " + httpResponse.statusCode.description
                completion(.failure(error))
            }
        }).resume()
        
    }
    
    func mergeTwoAccounts(completion: @escaping (Swift.Result<String, Error>) -> Void) {
        
        guard let url = buildWebasystUrl("/id/api/v1/profile/mergecode", parameters: [:]) else { return }
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let parameters: Parameters = [
            "Authorization": accessTokenString
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        for (key, value) in parameters {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse else { return }
            if let data = data,
               let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String:Any],
               let code = object?["code"] as? String {
                completion(.success(code))
            } else if httpResponse.statusCode == 409 {
                let error = NSError()
                completion(.failure(error))
            }
        }).resume()
        
    }
    
    func mergeResultCheck(completion: @escaping (Swift.Result<Bool, String>) -> Void) {
        
        guard let url = buildWebasystUrl("/id/api/v1/profile/mergeresult", parameters: [:]) else { return }
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let parameters: Parameters = [
            "Authorization": accessTokenString
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        for (key, value) in parameters {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            if let data = data,
               let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String:Any] ,
               let status = object?["status"] as? String {
                if status == "success" {
                    completion(.success(true))
                } else {
                    completion(.failure("error"))
                }
            }
        }).resume()
        
    }
    
    func deleteAccount(completion: @escaping (Swift.Result<Bool, String>) -> Void) {
        guard let url = buildWebasystUrl("/id/api/v1/terminate", parameters: [:]) else { return }
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let parameters: Parameters = [
            "Authorization": accessTokenString
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        for (key, value) in parameters {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            if let data = data,
               let httpResponse = response as? HTTPURLResponse,
               let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String:Any] ,
               let status = object?["deleted"] as? Bool {
                if status {
                    completion(.success(true))
                } else {
                    completion(.failure("Error code is" + " " + httpResponse.statusCode.description))
                }
            }
        }).resume()
    }
    
    func extendLicense(type: String, date: String, completion: @escaping (Swift.Result<String?, String>) -> Void) {
        
        guard let domain = UserDefaults.standard.string(forKey: "selectDomainUser"),
              let url = buildWebasystUrl("/id/api/v1/cloud/extend/", parameters: [:]) else { return }
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let parameters: Parameters = [
            "Authorization": accessTokenString
        ]
        let json = ["client_id": domain,
                    "expire_date": date,
                    "plan_id": type]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        if let encodedData = try? JSONSerialization.data(withJSONObject: json,
                                                         options: .fragmentsAllowed) {
            request.httpBody = encodedData
        }
        
        for (key, value) in parameters {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse else { return }
            if httpResponse.statusCode == 204 {
                completion(.success(nil))
            } else if let data = data, var error = String(data: data, encoding: .utf8) {
                error += " \n Error code is " + httpResponse.statusCode.description
                completion(.failure(error))
            }
        }).resume()
        
    }
    
}

//MARK: Private methods
extension WebasystUserNetworking {
    
    fileprivate func createDefaultGradient() -> Data? {
        let gradientImage = UIImage.gradientImageWithBounds(bounds: CGRect(x: 0, y: 0, width: 200, height: 200), colors: [self.hexStringToUIColor(hex: "#FF0078").cgColor, self.hexStringToUIColor(hex: "#FF5900").cgColor])
        let imageData = UIImagePNGRepresentation(gradientImage)
        return imageData
    }
    
    fileprivate func createGradient(from: String, to: String) -> Data? {
        let gradientImage = UIImage.gradientImageWithBounds(bounds: CGRect(x: 0, y: 0, width: 200, height: 200), colors: [self.hexStringToUIColor(hex: from).cgColor, self.hexStringToUIColor(hex: to).cgColor])
        let imageData = UIImagePNGRepresentation(gradientImage)
        return imageData
    }
    
    private func deleteNonActiveInstall(installList: [UserInstallCodable]) {
        
        guard let saveInstalls = profileInstallService?.getInstallList() else {
            return
        }
        
        var deleteInstall: [UserInstallCodable] = []
        
        if !installList.isEmpty {
            
            for _ in installList {
                for isntall in saveInstalls {
                    if !installList.contains(where: { $0.id == isntall.id }) {
                        let install = UserInstallCodable(name: isntall.name ?? "", domain: isntall.domain, id: isntall.id, accessToken: nil, url: isntall.url, image: nil)
                        deleteInstall.append(install)
                    }
                }
            }
            
        } else {
            
            for install in saveInstalls {
                let install = UserInstallCodable(name: install.name ?? "", domain: install.domain, id: install.id, accessToken: nil, url: install.url, image: nil)
                deleteInstall.append(install)
            }
            
        }
        
        for delete in deleteInstall {
            profileInstallService?.deleteInstall(clientId: delete.id)
        }
        
    }
    
    fileprivate func hexStringToUIColor (hex:String) -> UIColor {
        var cString:String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        if (cString.hasPrefix("#")) {
            cString.remove(at: cString.startIndex)
        }
        
        if ((cString.count) != 6) {
            return UIColor.gray
        }
        
        var rgbValue:UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)
        
        return UIColor(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: CGFloat(1.0)
        )
    }
    
}

extension String {
    func replace(target: String, withString: String) -> String {
        return self.replacingOccurrences(of: target, with: withString, options: NSString.CompareOptions.literal, range: nil)
    }
}

extension String: Error {}
