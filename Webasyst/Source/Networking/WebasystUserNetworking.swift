//
//  WebasystUserNetworking.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 17.05.2021.
//

import UIKit

final class WebasystUserNetworking: WebasystNetworkingManager {
    
    private let profileInstallService = WebasystDataModel()
    private let webasystNetworkingService = WebasystNetworking()
    private let networkingHelper = NetworkingHelper()
    private let timeoutChecker = WebasystTimeoutChecker()
    private let config = WebasystApp.config
    private let demoToken = "5f9db4d32d9a586c2daca4b45de23eb8"
    private lazy var queue = DispatchQueue(label: "\(config?.bundleId ?? "com.webasyst.x").WebasystUserNetworkingService", qos: .userInitiated)
    private let defaultImageUrl = "https://www.webasyst.com/wa-content/img/userpic96.jpg"
    
    func preloadUserData(_ completion: @escaping (Result<UserStatus, String>) -> ()) {
        if self.networkingHelper.isConnectedToNetwork {
            var isCanceled: Bool = false
            timeoutChecker.start {
                isCanceled = true
                let loc = WebasystApp.getDefaultLocalizedString(withKey: "preloadTimeout", comment: "Timeout for receiving a response from the server")
                completion(.failure(loc))
            }
            queue.async { [weak self] in
                guard let self = self, !isCanceled else { return }
                downloadUserData { [weak self] condition in
                    guard let self = self, !isCanceled else { return }
                    getInstallList { [weak self] result in
                        guard let self = self, !isCanceled else { return }
                        switch result {
                        case .success(let installs):
                            let clientIDs = installs.map { $0.id }
                            getAccessTokenApi(clientId: clientIDs) { [weak self] result in
                                guard let self = self, !isCanceled else { return }
                                UserDefaults.standard.setValue(false, forKey: "firstLaunch")
                                switch result {
                                case .success(let accessTokens):
                                    getAccessTokenInstall(installs, accessCodes: accessTokens) { [weak self] result in
                                        guard let self = self else { return }
                                        if isCanceled { return } else { timeoutChecker.stop() }
                                        switch result {
                                        case .success:
                                            if installs.isEmpty || condition {
                                                if condition && !installs.isEmpty {
                                                    completion(.success(.authorizedButProfileIsEmpty))
                                                } else if !condition && installs.isEmpty {
                                                    completion(.success(.authorizedButNoneInstalls))
                                                } else if condition && installs.isEmpty {
                                                    completion(.success(.authorizedButNoneInstallsAndProfileIsEmpty))
                                                }
                                            } else {
                                                completion(.success(.authorized))
                                            }
                                        case .failure:
                                            if condition {
                                                completion(.success(.authorizedButNoneInstallsAndProfileIsEmpty))
                                            } else {
                                                completion(.success(.authorizedButNoneInstalls))
                                            }
                                        }
                                    }
                                case .failure:
                                    timeoutChecker.stop()
                                    if condition {
                                        completion(.success(.authorizedButNoneInstallsAndProfileIsEmpty))
                                    } else {
                                        completion(.success(.authorizedButNoneInstalls))
                                    }
                                }
                            }
                        case .failure(let error):
                            timeoutChecker.stop()
                            completion(.failure(error))
                        }
                    }
                }
            }
        } else {
            let errorDescription = WebasystApp.getDefaultLocalizedString(withKey: "connectionAlertMessage", comment: "")
            completion(.failure(errorDescription))
        }
    }
    
    // MARK: - Send Apple ID email confirmation code
    internal func sendAppleIDEmailConfirmationCode(_ code: String, accessToken: Data, _ completion: @escaping (Result<Bool, String>) -> ()) {
        
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
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                do {
                    let authData = try JSONDecoder().decode(UserToken.self, from: response.data)
                    let accessTokenSuccess = KeychainManager.save(key: "accessToken", data: Data("Bearer \(authData.access_token)".utf8))
                    UserDefaults.standard.set(Data("Bearer \(authData.access_token)".utf8), forKey: "accessToken")
                    let refreshTokenSuccess = KeychainManager.save(key: "refreshToken", data: Data(authData.refresh_token.utf8))
                    if accessTokenSuccess == 0 && refreshTokenSuccess == 0 {
                        completion(.success(true))
                    }
                } catch {
                    let errorDescription = getErrorString(.decodingData(methodName: "sendAppleIDEmailConfirmationCode"))
                    print(errorDescription)
                    completion(.failure(errorDescription))
                }
            case .failure(let error):
                let errorDescription = getErrorString(.standart(error: error, methodName: "sendAppleIDEmailConfirmationCode"))
                print(errorDescription)
                completion(.failure(errorDescription))
            }
        }
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
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                do {
                    let userData = try JSONDecoder().decode(UserData.self, from: response.data)
                    let condition = userData.firstname.isEmpty || userData.lastname.isEmpty
                    completion(condition)
                    WebasystNetworkingManager().downloadImage(userData.userpic_original_crop) { [weak self] data in
                        guard let self = self else { return }
                        profileInstallService?.saveProfileData(userData, avatar: data)
                    }
                } catch {
                    let errorDescription = getErrorString(.decodingData(methodName: "downloadUserData"))
                    print(errorDescription)
                    completion(false)
                }
            case .failure(let error):
                let errorDescription = getErrorString(.standart(error: error, methodName: "downloadUserData"))
                print(errorDescription)
                completion(false)
            }
        }
    }
    
    public func changeUserData(_ profile: ProfileData,_ completion: @escaping (Result<ProfileData, Error>) -> Void) {
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
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if let userData = try? JSONDecoder().decode(UserData.self, from: response.data) {
                    WebasystNetworkingManager().downloadImage(userData.userpic_original_crop) { [weak self] data in
                        guard let self = self else { return }
                        profileInstallService?.saveProfileData(userData, avatar: data)
                        completion(.success(profile))
                    }
                } else {
                    let errorDescription = getErrorString(.decodingParameters(methodName: "changeUserData"))
                    print(errorDescription)
                    completion(.failure(errorDescription))
                }
            case .failure(let error):
                let errorDescription = getErrorString(.standart(error: error, methodName: "changeUserData"))
                print(errorDescription)
                completion(.failure(errorDescription))
            }
        }
    }
    
    public func deleteUserAvatar(_ completion: @escaping (Result<Bool, String>) -> ()) {
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
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                switch response.statusCode {
                case 204:
                    WebasystNetworkingManager().downloadImage(defaultImageUrl) { [weak self] data in
                        guard let self = self else { return }
                        profileInstallService?.saveNewAvatar(data)
                        completion(.success(true))
                    }
                default:
                    let errorDescription = getErrorString(.unowned(response: response, methodName: "deleteUserAvatar"))
                    print(errorDescription)
                    completion(.failure(errorDescription))
                }
            case .failure(let error):
                let errorDescription = getErrorString(.standart(error: error, methodName: "deleteUserAvatar"))
                print(errorDescription)
                completion(.failure(errorDescription))
            }
        }
    }
    
    public func updateUserAvatar(_ image: UIImage, _ completion: @escaping (Result<Bool, String>) -> ()) {
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        guard let url = buildWebasystUrl("/id/api/v1/profile/userpic", parameters: [:]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let imageData = image.jpegData(compressionQuality: 1)!
        
        let headers: Parameters = [
            "Authorization": accessTokenString,
            "Content-Type": "image/jpeg"
        ]
        
        request.httpBody = imageData
        
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                switch response.statusCode {
                case 201:
                    if let json = try? JSONSerialization.jsonObject(with: response.data) as? [String : Any],
                       let original_image = json["userpic_original_crop"] as? String {
                        WebasystNetworkingManager().downloadImage(original_image) { [weak self] data in
                            guard let self = self else { return }
                            profileInstallService?.saveNewAvatar(data)
                            completion(.success(true))
                        }
                    } else {
                        let errorDescription = getErrorString(.decodingParameters(methodName: "updateUserAvatar"))
                        print(errorDescription)
                        completion(.failure(errorDescription))
                    }
                default:
                    let errorDescription = getErrorString(.unowned(response: response, methodName: "updateUserAvatar"))
                    print(errorDescription)
                    completion(.failure(errorDescription))
                }
            case .failure(let error):
                let errorDescription = getErrorString(.standart(error: error, methodName: "updateUserAvatar"))
                print(errorDescription)
                completion(.failure(errorDescription))
            }
        }
    }
    
    //MARK: Get installation's list user
    public func getInstallList(_ completion: @escaping (Result<[UserInstallCodable], String>) -> ()) {
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let headers: Parameters = [
            "Authorization": accessTokenString
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/installations/", parameters: [:]) else {
            let errorDescription = "Webasyst error (getInstallList): Failed to retrieve list of user settings"
            print(errorDescription)
            completion(.failure(errorDescription))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                do {
                    let installList = try JSONDecoder().decode([UserInstallCodable].self, from: response.data)
                    let activeInstall = UserDefaults.standard.string(forKey: "selectDomainUser") ?? ""
                    if let install = installList.first?.id, activeInstall.isEmpty || !installList.contains(where: { $0.id == activeInstall }) {
                        UserDefaults.standard.setValue(install, forKey: "selectDomainUser")
                    }
                    completion(.success(installList))
                    deleteNonActiveInstall(installList: installList)
                } catch {
                    let errorDescription = getErrorString(.decodingData(methodName: "getInstallList"))
                    print(errorDescription)
                    completion(.failure(errorDescription))
                }
            case .failure(let error):
                if error == WebasystApp.getDefaultLocalizedString(withKey: "missingAuthToken", comment: "The authentication token is missing.") {
                    completion(.failure(error))
                } else {
                    let errorDescription = getErrorString(.standart(error: error, methodName: "getInstallList"))
                    print(errorDescription)
                    completion(.failure(errorDescription))
                }
                
            }
        }
    }
    
    func getAccessTokenApi(clientId: [String], _ completion: @escaping (Result<[String : Any], String>) -> ()) {
        
        let paramReqestApi: Dictionary<String, Any> = [
            "client_id": clientId
        ]
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        guard let url = buildWebasystUrl("/id/api/v1/auth/client/", parameters: [:]) else {
            completion(.failure("Webasyst error (getAccessTokenApi): 'Wrong target url'."))
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
            print("Webasyst error (getAccessTokenApi): '\(error.localizedDescription)'.")
        }
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                do {
                    if let json = try JSONSerialization.jsonObject(with: response.data) as? [String : Any] {
                        completion(.success(json))
                    } else {
                        let errorDescription = getErrorString(.decodingParameters(methodName: "getAccessTokenApi"))
                        print(errorDescription)
                        completion(.failure(errorDescription))
                    }
                } catch {
                    let errorDescription = getErrorString(.decodingData(methodName: "getAccessTokenApi"))
                    print(errorDescription)
                    completion(.failure(errorDescription))
                }
            case .failure(let error):
                let errorDescription = getErrorString(.standart(error: error, methodName: "getAccessTokenApi"))
                print(errorDescription)
                completion(.failure(errorDescription))
            }
        }
    }
    
    func getAccessTokenInstall(_ installList: [UserInstallCodable], accessCodes: [String : Any], _ completion: @escaping (Result<String, String>) -> ()) {
        
        guard let config = WebasystApp.config else { return }
        if let error = accessCodes["error_description"] as? String {
            print("Webasyst error (getAccessTokenInstall): Access codes not founded – '\(error)'.")
            return
        }
        
        var isCompleted: Bool = false
        
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
                print("Webasyst error (getAccessTokenInstall): Url install error.")
                break
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            do {
                try request.setMultipartFormData(parameters, encoding: String.Encoding.utf8)
            } catch {
                print("Webasyst error (getAccessTokenInstall): \(error.localizedDescription).")
            }
            
            createDataTaskSession(request) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    if let json = try? JSONSerialization.jsonObject(with: response.data) as? [String : String],
                        let accessToken = json["access_token"] {
                        let install = UserInstallCodable(name: "", domain: installList[index].domain, id: installList[index].id, accessToken: accessToken, url: installList[index].url, cloudPlanId: installList[index].cloudPlanId, cloudExpireDate: installList[index].cloudExpireDate, cloudTrial: installList[index].cloudTrial)
                        
                        if let activeInstall = UserDefaults.standard.string(forKey: "selectDomainUser"),
                           WebasystApp().getUserInstall(activeInstall) == nil {
                            UserDefaults.standard.setValue(install.id, forKey: "selectDomainUser")
                        }
                        
                        getInstallInfo(install) { _ in
                            if !isCompleted {
                                isCompleted = true
                                completion(.success(accessToken))
                            }
                        }
                    } else {
                        let errorDescription = getErrorString(.decodingParametersWithInstall(installDomain: installList[index].domain, methodName: "getAccessTokenInstall"))
                        print(errorDescription)
                        if index == installList.count - 1, !isCompleted {
                            isCompleted = true
                            completion(.failure(errorDescription))
                        }
                    }
                case .failure(let error):
                    let errorDescription = getErrorString(.standartWithInstall(error: error, installDomain: installList[index].domain, methodName: "getAccessTokenInstall"))
                    print(errorDescription)
                    if index == installList.count - 1, !isCompleted {
                        isCompleted = true
                        completion(.failure(errorDescription))
                    }
                }
            }
        }
    }
    
    func getInstallInfo(_ install: UserInstallCodable, loadSucces: @escaping (Bool) -> ()) {
        
        guard let url = URL(string: "\(install.url)/api.php/webasyst.getInfo?access_token=\(install.accessToken ?? "")&format=json") else {
            let errorDescription = "Webasyst error (getInstallInfo): Failed to generate a url when getting installation information."
            print(errorDescription)
            loadSucces(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        createDataTaskSession(request) { result in
            switch result {
            case .success(let response):
                let data = response.data
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
                            let errorDescription = "Webasyst error (getInstallInfo): \(info.name) \(error.localizedDescription)."
                            print(errorDescription)
                        }
                    case .gradient:
                        do {
                            let imageInfo = try JSONDecoder().decode(LogoGradient.self, from: data)
                            
                            let imageData = self.createGradient(from: imageInfo.logo?.gradient.from ?? "#FF0078", to: imageInfo.logo?.gradient.to ?? "#FF5900")
                            let install = UserInstall(name: info.name, domain: install.domain, id: install.id, accessToken: install.accessToken, url: install.url, image: imageData, imageLogo: false, logoText: info.logo?.text.value ?? "", logoTextColor: info.logo?.text.color ?? "", cloudPlanId: install.cloudPlanId, cloudExpireDate: install.cloudExpireDate, cloudTrial: install.cloudTrial)
                            
                            self.profileInstallService?.saveInstall(install)
                            self.profileInstallService?.createNew()
                            loadSucces(true)
                        } catch {
                            let errorDescription = "Webasyst error (getInstallInfo): \(info.name) \(error.localizedDescription)."
                            print(errorDescription)
                        }
                    case .unknown:
                        let imageData = self.createDefaultGradient()
                        
                        let newInstall = UserInstall(name: info.name, domain: install.domain , id: install.id , accessToken: install.accessToken, url: install.url, image: imageData, imageLogo: false, logoText: info.logo?.text.value ?? "", logoTextColor: info.logo?.text.color ?? "", cloudPlanId: install.cloudPlanId, cloudExpireDate: install.cloudExpireDate, cloudTrial: install.cloudTrial)
                        
                        self.profileInstallService?.saveInstall(newInstall)
                        self.profileInstallService?.createNew()
                        loadSucces(true)
                    }
                } catch {
                    let imageData = self.createDefaultGradient()
                    let newInstall = UserInstall(name: install.domain, domain: install.domain , id: install.id , accessToken: install.accessToken, url: install.url, image: imageData, imageLogo: false, logoText: "", logoTextColor: "", cloudPlanId: install.cloudPlanId, cloudExpireDate: install.cloudExpireDate, cloudTrial: install.cloudTrial)
                    self.profileInstallService?.saveInstall(newInstall)
                    loadSucces(true)
                    let errorDescription = "Webasyst warning (getInstallInfo): \(install.domain) unable to decode model – '\(error.localizedDescription)'."
                    print(errorDescription)
                }
            case .failure(let error):
                let imageData = self.createDefaultGradient()
                let newInstall = UserInstall(name: install.domain, domain: install.domain , id: install.id , accessToken: install.accessToken, url: install.url, image: imageData, imageLogo: false, logoText: "", logoTextColor: "", cloudPlanId: install.cloudPlanId, cloudExpireDate: install.cloudExpireDate, cloudTrial: install.cloudTrial)
                self.profileInstallService?.saveInstall(newInstall)
                loadSucces(true)
                let errorDescription = "Webasyst error (getInstallInfo): '\(error)'."
                print(errorDescription)
            }
        }
    }
    
    func createWebasystAccount(bundle: String, plainId: String, accountName: String?, _ completion: @escaping (Result<(id: String, url: String), String>) -> ()) {
        
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
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                do {
                    if let dict = try JSONSerialization.jsonObject(with: response.data, options: .mutableContainers) as? [String : Any],
                       let id = dict["id"] as? String,
                       let url = dict["url"] as? String,
                       let domain = dict["domain"] as? String {
                        var newInstall: [UserInstallCodable] = []
                        getAccessTokenApi(clientId: [id]) { [weak self] result in
                            guard let self = self else { return }
                            switch result {
                            case .success(let json):
                                let install = UserInstallCodable(name: nil, domain: domain, id: id, accessToken: nil, url: url, image: nil)
                                newInstall.append(install)
                                getAccessTokenInstall(newInstall, accessCodes: json) { result in
                                    switch result {
                                    case .success:
                                        completion(.success((id: id, url: url)))
                                    case .failure(let error):
                                        completion(.failure(error))
                                    }
                                }
                            case .failure:
                                let loc = WebasystApp.getDefaultLocalizedString(withKey: "failedToGetAccessTokenForCreatedAccount", comment: "Missing access token")
                                let errorDescription = "Webasyst error (createWebasystAccount): " + loc
                                print(errorDescription)
                                completion(.failure(errorDescription))
                            }
                        }
                    } else {
                        let errorDescription = getErrorString(.decodingParameters(methodName: "createWebasystAccount"))
                        print(errorDescription)
                        completion(.failure(errorDescription))
                    }
                } catch {
                    let errorDescription = getErrorString(.decodingData(methodName: "createWebasystAccount"))
                    print(errorDescription)
                    completion(.failure(errorDescription))
                }
            case .failure(let error):
                let errorDescription = getErrorString(.standart(error: error, methodName: "createWebasystAccount"))
                print(errorDescription)
                completion(.failure(errorDescription))
            }
        }
    }
    
    func renameWebasystAccount(clientId: String, domain: String, _ completion: @escaping (Result<Bool, String>) -> ()) {
        
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
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                switch response.statusCode {
                case 204:
                    completion(.success(true))
                default:
                    let errorDescription = getErrorString(.unowned(response: response, methodName: "renameWebasystAccount"))
                    print(errorDescription)
                    completion(.failure(errorDescription))
                }
            case .failure(let error):
                let errorDescription = getErrorString(.standart(error: error, methodName: "renameWebasystAccount"))
                print(errorDescription)
                completion(.failure(errorDescription))
            }
        }
    }
    
    func singUpUser(_ completion: @escaping (Bool) -> ()) {
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let headerRequest: Parameters = [
            "Authorization": accessTokenString
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/delete/", parameters: [:]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(headerRequest.first?.value ?? "", forHTTPHeaderField: headerRequest.first?.key ?? "")
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                completion(true)
            case .failure(let error):
                let errorDescription = getErrorString(.standart(error: error, methodName: "singUpUser"))
                print(errorDescription)
                completion(false)
            }
        }
    }
    
    func checkAppInstall(app: String, _ completion: @escaping (Result<String?, String>) -> Void) {
        
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
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if let _ = try? JSONSerialization.jsonObject(with: response.data, options: .fragmentsAllowed) as? Bool {
                    completion(.success(nil))
                } else {
                    let errorDescription = getErrorString(.decodingParameters(methodName: "checkAppInstall"))
                    completion(.failure(errorDescription))
                }
            case .failure(let error):
                let errorDescription = getErrorString(.standart(error: error, methodName: "checkAppInstall"))
                completion(.failure(errorDescription))
            }
        }
    }
    
    func checkInstallLicense(app: String, _ completion: @escaping (Result<String?, String>) -> Void) {
        
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
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if response.statusCode == 204 {
                    completion(.success(nil))
                } else {
                    let errorDescription = getErrorString(.unowned(response: response, methodName: "checkInstallLicense"))
                    completion(.failure(errorDescription))
                }
            case .failure(let error):
                let errorDescription = getErrorString(.standart(error: error, methodName: "checkInstallLicense"))
                completion(.failure(errorDescription))
            }
        }
    }
    
    func mergeTwoAccounts(_ completion: @escaping (Result<String, Error>) -> Void) {
        
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
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if let object = try? JSONSerialization.jsonObject(with: response.data, options: .fragmentsAllowed) as? [String : Any],
                   let code = object["code"] as? String {
                    completion(.success(code))
                } else {
                    let errorDescription = getErrorString(.decodingParameters(methodName: "mergeTwoAccounts"))
                    completion(.failure(errorDescription))
                }
            case .failure(let error):
                let errorDescription = getErrorString(.standart(error: error, methodName: "mergeTwoAccounts"))
                completion(.failure(errorDescription))
            }
        }
    }
    
    func mergeResultCheck(_ completion: @escaping (Result<Bool, String>) -> Void) {
        
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
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if let object = try? JSONSerialization.jsonObject(with: response.data, options: .fragmentsAllowed) as? [String : Any],
                   let status = object["status"] as? String {
                    if status == "success" {
                        completion(.success(true))
                    } else {
                        let errorDescription = getErrorString(.decodingParameters(methodName: "mergeResultCheck"))
                        completion(.failure(errorDescription))
                    }
                } else {
                    let errorDescription = getErrorString(.decodingData(methodName: "mergeResultCheck"))
                    completion(.failure(errorDescription))
                }
            case .failure(let error):
                let errorDescription = getErrorString(.standart(error: error, methodName: "mergeResultCheck"))
                completion(.failure(errorDescription))
            }
        }
    }
    
    func deleteAccount(_ completion: @escaping (Result<Bool, String>) -> Void) {
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
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if let object = try? JSONSerialization.jsonObject(with: response.data, options: .fragmentsAllowed) as? [String : Any],
                   let status = object["deleted"] as? Bool {
                    if status {
                        completion(.success(true))
                    } else {
                        let errorDescription = getErrorString(.decodingParameters(methodName: "deleteAccount"))
                        completion(.failure(errorDescription))
                    }
                } else {
                    let errorDescription = getErrorString(.decodingData(methodName: "deleteAccount"))
                    completion(.failure(errorDescription))
                }
            case .failure(let error):
                let errorDescription = getErrorString(.standart(error: error, methodName: "deleteAccount"))
                completion(.failure(errorDescription))
            }
        }
    }
    
    func extendLicense(type: String, date: String, _ completion: @escaping (Result<String?, String>) -> Void) {
        
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
        
        createDataTaskSession(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                switch response.statusCode {
                case 204:
                    completion(.success(nil))
                default:
                    let errorDescription = getErrorString(.unowned(response: response, methodName: "extendLicense"))
                    completion(.failure(errorDescription))
                }
            case .failure(let error):
                let errorDescription = getErrorString(.standart(error: error, methodName: "extendLicense"))
                completion(.failure(errorDescription))
            }
        }
    }
}

//MARK: Private methods

private
extension WebasystUserNetworking {
    
    struct ServerResponse {
        let data: Data
        let response: URLResponse
        let statusCode: Int
    }
    
    func createDataTaskSession(_ request: URLRequest, _ completion: @escaping (Result<ServerResponse, String>) -> ()) {
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let response = response as? HTTPURLResponse else {
                let errorDescription = WebasystApp.getDefaultLocalizedString(withKey: "unownedStatusCode", comment: "Unowned server response status code")
                completion(.failure(errorDescription))
                return
            }
            
            if let error = error {
                completion(.failure("Responsed error: " + error.localizedDescription))
                return
            }
            
            guard let data = data else {
                let errorDescription = WebasystApp.getDefaultLocalizedString(withKey: "emptyResponsedData", comment: "Empty responsed data")
                completion(.failure(errorDescription))
                return
            }
            
            switch response.statusCode {
            case 200...299:
                let serverResponse = ServerResponse(data: data, response: response, statusCode: response.statusCode)
                completion(.success(serverResponse))
            case 400...504:
                switch response.statusCode {
                case 400...401:
                    let errorDescription = WebasystApp.getDefaultLocalizedString(withKey: "missingAuthToken", comment: "The authentication token is missing.")
                    completion(.failure(errorDescription))
                case 404:
                    let errorDescription = WebasystApp.getDefaultLocalizedString(withKey: "404Error", comment: "Server send 404 error")
                    completion(.failure(errorDescription))
                default:
                    do {
                        let errorModel = try JSONDecoder().decode(ErrorModel.self, from: data)
                        
                        var error: String?
                        if let e = errorModel.errorDescription, !e.isEmpty {
                            error = e
                        } else if let e = errorModel.error {
                            error = e
                        }
                        
                        if let error = error {
                            if error == "prepared_account_not_exists" {
                                let errorDescription = WebasystApp.getDefaultLocalizedString(withKey: "preparedAccountNotExists", comment: "Prepared account not exists")
                                completion(.failure(errorDescription))
                            } else {
                                let loc = WebasystApp.getDefaultLocalizedString(withKey: "serverSentError", comment: "Server send error")
                                let errorDescription = loc + "\(error)"
                                completion(.failure(errorDescription))
                            }
                        } else {
                            let loc = WebasystApp.getDefaultLocalizedString(withKey: "unownedErrorWithStatusCode", comment: "Unowned error with response status code")
                            let errorDescription = loc.replacingOccurrences(of: "%CODE%", with: response.statusCode.description)
                            completion(.failure(errorDescription))
                        }
                    } catch {
                        let loc = WebasystApp.getDefaultLocalizedString(withKey: "unownedErrorWithStatusCode", comment: "Unowned error with response status code")
                        let errorDescription = loc.replacingOccurrences(of: "%CODE%", with: response.statusCode.description) + " " + error.localizedDescription
                        completion(.failure(errorDescription))
                    }
                }
            default:
                let loc = WebasystApp.getDefaultLocalizedString(withKey: "unownedErrorWithStatusCode", comment: "Unowned error with response status code")
                let errorDescription = loc.replacingOccurrences(of: "%CODE%", with: response.statusCode.description)
                completion(.failure(errorDescription))
            }
        }
        .resume()
    }
    
    enum ServerErrorDescriptionType {
        case unowned(response: ServerResponse, methodName: String)
        case decodingData(methodName: String)
        case decodingParameters(methodName: String)
        case decodingParametersWithInstall(installDomain: String, methodName: String)
        case standart(error: String, methodName: String)
        case standartWithInstall(error: String, installDomain: String, methodName: String)
    }
    
    func getErrorString(_ type: ServerErrorDescriptionType) -> String {
        switch type {
        case .unowned(let response, let methodName):
            let loc = WebasystApp.getDefaultLocalizedString(withKey: "unownedServerError", comment: "Unowned server error")
            let dataStr = String(data: response.data, encoding: .utf8) ?? ""
            let errorDescription = loc
                .replacingOccurrences(of: "%METHOD%", with: methodName)
                .replacingOccurrences(of: "%DATA%", with: dataStr)
                .replacingOccurrences(of: "%CODE%", with: response.statusCode.description)
            return errorDescription
        case .decodingData(let methodName):
            let loc = WebasystApp.getDefaultLocalizedString(withKey: "unableToDecodeResponsedData", comment: "Unable to decode server response")
            let errorDescription = "Webasyst error (\(methodName)): " + loc
            return errorDescription
        case .decodingParameters(let methodName):
            let loc = WebasystApp.getDefaultLocalizedString(withKey: "unableToGetDecodedParameters", comment: "Unable to get decoded parameters")
            let errorDescription = "Webasyst error (\(methodName)): " + loc
            return errorDescription
        case .decodingParametersWithInstall(let installDomain, let methodName):
            let loc = WebasystApp.getDefaultLocalizedString(withKey: "unableToGetDecodedParameters", comment: "Unable to get decoded parameters")
            let errorDescription = "Webasyst error (\(methodName)): \(installDomain) – " + loc
            return errorDescription
        case .standart(let error, let methodName):
            return "Webasyst error (\(methodName)): '\(error)'"
        case .standartWithInstall(let error, let installDomain, let methodName):
            return "Webasyst error (\(methodName)): \(installDomain) – '\(error)'"
        }
    }
    
    func createDefaultGradient() -> Data? {
        let gradientImage = UIImage.init(gradientColors: [self.hexStringToUIColor(hex: "#FF0078"),
                                                          self.hexStringToUIColor(hex: "#FF5900")],
                                         size: CGSize(width: 200, height: 200))
        let imageData = gradientImage?.pngData()
        return imageData
    }
    
    func createGradient(from: String, to: String) -> Data? {
        let gradientImage = UIImage.init(gradientColors: [self.hexStringToUIColor(hex: from),
                                                          self.hexStringToUIColor(hex: to)],
                                         size: CGSize(width: 200, height: 200))
        let imageData = gradientImage?.pngData()
        return imageData
    }
    
    func deleteNonActiveInstall(installList: [UserInstallCodable]) {
        
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
    
    func hexStringToUIColor(hex: String) -> UIColor {
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
