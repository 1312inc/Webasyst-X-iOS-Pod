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
    private let demoToken = "5f9db4d32d9a586c2daca4b45de23eb8"
    private lazy var queue = DispatchQueue(label: "\(WebasystApp.config?.bundleId ?? "com.webasyst.x").WebasystUserNetworkingService", qos: .userInitiated)
    private let defaultImageUrl = "https://www.webasyst.com/wa-content/img/userpic96.jpg"
    
    func preloadUserData(_ completion: @escaping (WebasystResult<UserStatus>) -> ()) {
        if self.networkingHelper.isConnectedToNetwork {
            
            let timeoutChecker = WebasystTimeoutChecker()
            
            var isCanceled: Bool = false
            
            timeoutChecker.start { [weak self] in
                guard let self else { return }
                
                isCanceled = true
                
                let loc = WebasystApp.getDefaultLocalizedString(withKey: "preloadTimeout", comment: "Timeout for receiving a response from the server")
                
                let webasystError = WebasystError(localizedError: loc)
                
                let errorType = ErrorTypeModel(error: webasystError, type: .standart(), methodName: "preloadUserData")
                let error = getError(errorType)
                completion(.failure(error))
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
                                    getAccessTokenInstall(installs, accessCodes: accessTokens) { result in
                                        if isCanceled {
                                            return
                                        } else {
                                            timeoutChecker.stop()
                                        }
                                        
                                        switch result {
                                        case .success:
                                            if installs.isEmpty || condition {
                                                if condition && !installs.isEmpty {
                                                    completion(.success(.authorizedButProfileIsEmpty))
                                                } else if !condition && installs.isEmpty {
                                                    completion(.success(.authorizedButNoneInstalls))
                                                } else if condition && installs.isEmpty {
                                                    completion(.success(.authorizedButNoneInstallsAndProfileIsEmpty))
                                                } else {
                                                    completion(.success(.authorized))
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
            let loc = WebasystApp.getDefaultLocalizedString(withKey: "connectionAlertMessage")
            
            let webasystError = WebasystError(localizedError: loc)
            
            let errorType = ErrorTypeModel(error: webasystError, type: .standart(), methodName: "preloadUserData")
            let error = getError(errorType)
            completion(.failure(error))
        }
    }
    
    internal func restoreTokensFromGroup(_ completion: @escaping (Bool) -> ()) {
        guard let config = WebasystApp.config else { return }
        
        let accessToken = KeychainManager.getToken(.accessToken)
        
        let headers: Parameters = [
            "Authorization": accessToken
        ]
        
        let paramsRequest: Parameters = [
            "client_id": config.clientId
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/auth/cross-app/", parameters: [:]) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        if let encodedData = try? JSONSerialization.data(withJSONObject: paramsRequest, options: .fragmentsAllowed) {
            request.httpBody = encodedData
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
                                }
                            } catch {
                                completion(false)
                                print(NSError(domain: "Webasyst error: decode error (restoreTokensFromGroup) \n\(error).", code: 400, userInfo: nil))
                            }
                        }
                    default:
                        completion(false)
                    }
                }
            }.resume()
        }
    }
    
    // MARK: - Send Apple ID email confirmation code
    internal func sendAppleIDEmailConfirmationCode(_ code: String, accessToken: Data, _ completion: @escaping (WebasystResult<Bool>) -> ()) {
        
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
                let statusCode = response.statusCode
                
                do {
                    let authData = try JSONDecoder().decode(UserToken.self, from: response.data)
                    
                    let accessTokenData = Data("Bearer \(authData.access_token)".utf8)
                    let refreshTokenData = Data(authData.refresh_token.utf8)
                    
                    let accessTokenSuccess = KeychainManager.save(.accessToken, data: accessTokenData)
                    let refreshTokenSuccess = KeychainManager.save(.refreshToken, data: refreshTokenData)
                    
                    if accessTokenSuccess == 0 && refreshTokenSuccess == 0 {
                        completion(.success(true))
                    }
                } catch let error {
                    let loc = "\(error)"
                    let webasystError = WebasystError(localizedError: loc, statusCode: statusCode)
                    let errorType = ErrorTypeModel(error: webasystError, type: .decodingData, methodName: "sendAppleIDEmailConfirmationCode")
                    let error = getError(errorType)
                    completion(.failure(error))
                }
            case .failure(let error):
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "sendAppleIDEmailConfirmationCode")
                let error = getError(errorType)
                completion(.failure(error))
            }
        }
    }
    
    //MARK: Download user data
    internal func downloadUserData(_ completion: @escaping (Bool) -> Void) {
        let accessToken = KeychainManager.getToken(.accessToken)
        
        let headers: Parameters = [
            "Authorization": accessToken
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
                let statusCode = response.statusCode
                
                do {
                    let userData = try JSONDecoder().decode(UserData.self, from: response.data)
                    let condition = userData.firstname.isEmpty || userData.lastname.isEmpty
                    completion(condition)
                    WebasystNetworkingManager().downloadImage(userData.userpic_original_crop) { [weak self] data in
                        guard let self = self else { return }
                        profileInstallService?.saveProfileData(userData, avatar: data)
                    }
                } catch let error {
                    let loc = "\(error)"
                    let webasystError = WebasystError(localizedError: loc, statusCode: statusCode)
                    let errorType = ErrorTypeModel(error: webasystError, type: .decodingData, methodName: "downloadUserData")
                    let error = getError(errorType)
                    print(error.localizedError)
                    completion(false)
                }
            case .failure(let error):
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "downloadUserData")
                let error = getError(errorType)
                print(error.localizedError)
                completion(false)
            }
        }
    }
    
    public func changeUserData(_ profile: ProfileData,_ completion: @escaping (WebasystResult<ProfileData>) -> Void) {
        let accessToken = KeychainManager.getToken(.accessToken)
        
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
            "Authorization" : accessToken,
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
                    let errorType = ErrorTypeModel(type: .decodingParameters(), methodName: "changeUserData")
                    let error = getError(errorType)
                    completion(.failure(error))
                }
            case .failure(let error):
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "changeUserData")
                let error = getError(errorType)
                completion(.failure(error))
            }
        }
    }
    
    public func deleteUserAvatar(_ completion: @escaping (WebasystResult<Bool>) -> ()) {
        let accessToken = KeychainManager.getToken(.accessToken)
        
        let headers: Parameters = [
            "Authorization": accessToken
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
                    let errorType = ErrorTypeModel(type: .unowned(response: response), methodName: "deleteUserAvatar")
                    let error = getError(errorType)
                    completion(.failure(error))
                }
            case .failure(let error):
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "deleteUserAvatar")
                let error = getError(errorType)
                completion(.failure(error))
            }
        }
    }
    
    public func updateUserAvatar(_ image: UIImage, _ completion: @escaping (WebasystResult<Bool>) -> ()) {
        let accessToken = KeychainManager.getToken(.accessToken)
        
        guard let url = buildWebasystUrl("/id/api/v1/profile/userpic", parameters: [:]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let imageData = image.jpegData(compressionQuality: 1)!
        
        let headers: Parameters = [
            "Authorization": accessToken,
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
                        let errorType = ErrorTypeModel(type: .decodingParameters(), methodName: "updateUserAvatar")
                        let error = getError(errorType)
                        completion(.failure(error))
                    }
                default:
                    let errorType = ErrorTypeModel(type: .unowned(response: response), methodName: "updateUserAvatar")
                    let error = getError(errorType)
                    completion(.failure(error))
                }
            case .failure(let error):
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "updateUserAvatar")
                let error = getError(errorType)
                completion(.failure(error))
            }
        }
    }
    
    //MARK: Get installation's list user
    public func getInstallList(_ completion: @escaping (WebasystResult<[UserInstallCodable]>) -> ()) {
        
        let accessToken = KeychainManager.getToken(.accessToken)
        
        let headers: Parameters = [
            "Authorization": accessToken
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/installations/", parameters: [:]) else {
            let loc = WebasystApp.getDefaultLocalizedString(withKey: "error.installList")
            
            let webasystError = WebasystError(localizedError: loc)
            
            let errorType = ErrorTypeModel(error: webasystError, type: .standart(), methodName: "getInstallList")
            let error = getError(errorType)
            completion(.failure(error))
            
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
                let statusCode = response.statusCode
                
                do {
                    let installList = try JSONDecoder().decode([UserInstallCodable].self, from: response.data)
                    let activeInstall = UserDefaults.standard.string(forKey: "selectDomainUser") ?? ""
                    if let install = installList.first?.id, activeInstall.isEmpty || !installList.contains(where: { $0.id == activeInstall }) {
                        UserDefaults.standard.setValue(install, forKey: "selectDomainUser")
                    }
                    completion(.success(installList))
                    deleteNonActiveInstall(installList: installList)
                } catch let error {
                    let loc = "\(error)"
                    let webasystError = WebasystError(localizedError: loc, statusCode: statusCode)
                    let errorType = ErrorTypeModel(error: webasystError, type: .decodingData, methodName: "getInstallList")
                    let error = getError(errorType)
                    completion(.failure(error))
                }
            case .failure(let error):
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "getInstallList")
                let error = getError(errorType)
                completion(.failure(error))
            }
        }
    }
    
    func getAccessTokenApi(clientId: [String], _ completion: @escaping (WebasystResult<[String : Any]>) -> ()) {
        
        let paramReqestApi: Dictionary<String, Any> = [
            "client_id": clientId
        ]
        
        let accessToken = KeychainManager.getToken(.accessToken)
        
        guard let url = buildWebasystUrl("/id/api/v1/auth/client/", parameters: [:]) else {
            let loc = WebasystApp.getDefaultLocalizedString(withKey: "error.wrongUrl")
            
            let webasystError = WebasystError(localizedError: loc)
            
            let errorType = ErrorTypeModel(error: webasystError, type: .standart(), methodName: "getAccessTokenApi")
            let error = getError(errorType)
            completion(.failure(error))
            
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(accessToken, forHTTPHeaderField: "Authorization")
        
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
                let statusCode = response.statusCode
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: response.data) as? [String : Any] {
                        completion(.success(json))
                    } else {
                        let errorType = ErrorTypeModel(type: .decodingParameters(), methodName: "getAccessTokenApi")
                        let error = getError(errorType)
                        completion(.failure(error))
                    }
                } catch let error {
                    let loc = "\(error)"
                    let webasystError = WebasystError(localizedError: loc, statusCode: statusCode)
                    let errorType = ErrorTypeModel(error: webasystError, type: .decodingData, methodName: "getAccessTokenApi")
                    let error = getError(errorType)
                    completion(.failure(error))
                }
            case .failure(let error):
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "getAccessTokenApi")
                let error = getError(errorType)
                completion(.failure(error))
            }
        }
    }
    
    func getAccessTokenInstall(_ installList: [UserInstallCodable], accessCodes: [String : Any], _ completion: @escaping (WebasystResult<String>) -> ()) {
        
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
                        let errorType = ErrorTypeModel(type: .decodingParameters(domain: installList[index].domain), methodName: "getAccessTokenInstall")
                        let error = getError(errorType)
                        if index == installList.count - 1, !isCompleted {
                            isCompleted = true
                            completion(.failure(error))
                        }
                    }
                case .failure(let error):
                    let errorType = ErrorTypeModel(error: error, type: .standart(domain: installList[index].domain), methodName: "getAccessTokenInstall")
                    let error = getError(errorType)
                    if index == installList.count - 1, !isCompleted {
                        isCompleted = true
                        completion(.failure(error))
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
    
    func createWebasystAccount(bundle: String, plainId: String, accountDomain: String?, accountName: String?, _ completion: @escaping (WebasystResult<(id: String, url: String)>) -> ()) {
        
        let accessToken = KeychainManager.getToken(.accessToken)
        
        let headers: Parameters = [
            "Authorization": accessToken
        ]
        
        var parametersRequest: Parameters = [
            "bundle": bundle,
            "plan_id": plainId
        ]
        
        if let accountDomain = accountDomain {
            parametersRequest["userdomain"] = accountDomain
        }
        
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
            guard let self else { return }
            
            switch result {
            case .success(let response):
                let statusCode = response.statusCode
                
                do {
                    if let dict = try JSONSerialization.jsonObject(with: response.data, options: .mutableContainers) as? [String : Any],
                       let id = dict["id"] as? String,
                       let url = dict["url"] as? String,
                       let domain = dict["domain"] as? String {
                        var newInstall: [UserInstallCodable] = []
                        
                        getAccessTokenApi(clientId: [id]) { [weak self] result in
                            guard let self else { return }
                            
                            switch result {
                            case .success(let json):
                                let install = UserInstallCodable(name: nil, domain: domain, id: id, accessToken: nil, url: url, image: nil)
                                newInstall.append(install)
                                getAccessTokenInstall(newInstall, accessCodes: json) { [weak self] result in
                                    guard let self else { return }
                                    
                                    switch result {
                                    case .success:
                                        completion(.success((id: id, url: url)))
                                    case .failure(let error):
                                        let errorType = ErrorTypeModel(error: error, type: .standart(domain: domain), methodName: "createWebasystAccount")
                                        let error = getError(errorType)
                                        completion(.failure(error))
                                    }
                                }
                            case .failure(let error):
                                let loc = WebasystApp.getDefaultLocalizedString(withKey: "failedToGetAccessTokenForCreatedAccount", comment: "Missing access token") + " " + error.localizedError
                                
                                let webasystError = WebasystError(localizedError: loc, statusCode: error.statusCode, errorValue: error.errorValue)
                                
                                let errorType = ErrorTypeModel(error: webasystError, type: .standart(domain: domain), methodName: "createWebasystAccount")
                                let error = getError(errorType)
                                completion(.failure(error))
                            }
                        }
                    } else {
                        let errorType = ErrorTypeModel(type: .decodingParameters(), methodName: "createWebasystAccount")
                        let error = getError(errorType)
                        completion(.failure(error))
                    }
                } catch let error {
                    let loc = "\(error)"
                    let webasystError = WebasystError(localizedError: loc, statusCode: statusCode)
                    let errorType = ErrorTypeModel(error: webasystError, type: .decodingData, methodName: "createWebasystAccount")
                    let error = getError(errorType)
                    completion(.failure(error))
                }
            case .failure(let error):
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "createWebasystAccount")
                let error = getError(errorType)
                completion(.failure(error))
            }
        }
    }
    
    func renameWebasystAccount(clientId: String, domain: String, _ completion: @escaping (WebasystResult<Bool>) -> ()) {
        
        let accessToken = KeychainManager.getToken(.accessToken)
        
        let headers: Parameters = [
            "Authorization": accessToken
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
                    let errorType = ErrorTypeModel(type: .unowned(response: response), methodName: "renameWebasystAccount")
                    let error = getError(errorType)
                    completion(.failure(error))
                }
            case .failure(let error):
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "renameWebasystAccount")
                let error = getError(errorType)
                completion(.failure(error))
            }
        }
    }
    
    func singUpUser(_ completion: @escaping (Bool) -> ()) {
        let accessToken = KeychainManager.getToken(.accessToken)
        
        let headerRequest: Parameters = [
            "Authorization": accessToken
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
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "singUpUser")
                let error = getError(errorType)
                print(error.localizedError)
                completion(false)
            }
        }
    }
    
    func checkAppInstall(app: String, _ completion: @escaping (WebasystResult<String?>) -> Void) {
        
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
                    let errorType = ErrorTypeModel(type: .decodingParameters(), methodName: "checkAppInstall")
                    let error = getError(errorType)
                    completion(.failure(error))
                }
            case .failure(let error):
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "checkAppInstall")
                let error = getError(errorType)
                completion(.failure(error))
            }
        }
    }
    
    func checkInstallLicense(app: String, _ completion: @escaping (WebasystResult<String?>) -> Void) {
        
        guard let domain = UserDefaults.standard.string(forKey: "selectDomainUser"),
              let url = buildWebasystUrl("/id/api/v1/licenses/force/", parameters: [:]) else { return }
        
        let accessToken = KeychainManager.getToken(.accessToken)
        
        let parameters: Parameters = [
            "Authorization": accessToken
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
                    let errorType = ErrorTypeModel(type: .unowned(response: response), methodName: "checkInstallLicense")
                    let error = getError(errorType)
                    completion(.failure(error))
                }
            case .failure(let error):
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "checkInstallLicense")
                let error = getError(errorType)
                completion(.failure(error))
            }
        }
    }
    
    func mergeTwoAccounts(_ completion: @escaping (WebasystResult<String>) -> Void) {
        
        guard let url = buildWebasystUrl("/id/api/v1/profile/mergecode", parameters: [:]) else { return }
        
        let accessToken = KeychainManager.getToken(.accessToken)
        
        let parameters: Parameters = [
            "Authorization": accessToken
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
                    let errorType = ErrorTypeModel(type: .decodingParameters(), methodName: "mergeTwoAccounts")
                    let error = getError(errorType)
                    completion(.failure(error))
                }
            case .failure(let error):
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "mergeTwoAccounts")
                let error = getError(errorType)
                completion(.failure(error))
            }
        }
    }
    
    func mergeResultCheck(_ completion: @escaping (WebasystResult<Bool>) -> Void) {
        
        guard let url = buildWebasystUrl("/id/api/v1/profile/mergeresult", parameters: [:]) else { return }
        
        let accessToken = KeychainManager.getToken(.accessToken)
        
        let parameters: Parameters = [
            "Authorization": accessToken
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
                        let errorType = ErrorTypeModel(type: .decodingParameters(), methodName: "mergeResultCheck")
                        let error = getError(errorType)
                        completion(.failure(error))
                    }
                } else {
                    let errorType = ErrorTypeModel(type: .decodingData, methodName: "mergeResultCheck")
                    let error = getError(errorType)
                    completion(.failure(error))
                }
            case .failure(let error):
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "mergeResultCheck")
                let error = getError(errorType)
                completion(.failure(error))
            }
        }
    }
    
    func deleteAccount(_ completion: @escaping (WebasystResult<Bool>) -> Void) {
        guard let url = buildWebasystUrl("/id/api/v1/terminate", parameters: [:]) else { return }
        
        let accessToken = KeychainManager.getToken(.accessToken)
        
        let parameters: Parameters = [
            "Authorization": accessToken
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
                        let errorType = ErrorTypeModel(type: .decodingParameters(), methodName: "deleteAccount")
                        let error = getError(errorType)
                        completion(.failure(error))
                    }
                } else {
                    let errorType = ErrorTypeModel(type: .decodingData, methodName: "deleteAccount")
                    let error = getError(errorType)
                    completion(.failure(error))
                }
            case .failure(let error):
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "deleteAccount")
                let error = getError(errorType)
                completion(.failure(error))
            }
        }
    }
    
    func extendLicense(type: String, date: String, _ completion: @escaping (WebasystResult<String?>) -> Void) {
        
        guard let domain = UserDefaults.standard.string(forKey: "selectDomainUser"),
              let url = buildWebasystUrl("/id/api/v1/cloud/extend/", parameters: [:]) else { return }
        
        let accessToken = KeychainManager.getToken(.accessToken)
        
        let parameters: Parameters = [
            "Authorization": accessToken
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
                    let errorType = ErrorTypeModel(type: .unowned(response: response), methodName: "extendLicense")
                    let error = getError(errorType)
                    completion(.failure(error))
                }
            case .failure(let error):
                let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "extendLicense")
                let error = getError(errorType)
                completion(.failure(error))
            }
        }
    }
}

//MARK: Private methods

private
extension WebasystUserNetworking {
    
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
