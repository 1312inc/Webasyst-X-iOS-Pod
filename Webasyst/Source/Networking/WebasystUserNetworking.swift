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
    private let demoToken = "5f9db4d32d9a586c2daca4b45de23eb8"
    private lazy var queue = DispatchQueue(label: "\(WebasystApp.config?.bundleId ?? "com.webasyst.x").WebasystUserNetworkingService", qos: .userInitiated)
    private let defaultImageUrl = "https://\(WebasystApp.getLocalizedDomain())/wa-content/img/userpic96.jpg"
    
    func preloadUserData(_ completion: @escaping (WebasystResult<UserStatus>) -> ()) {
        WebasystAuthSession.onMain {
            let generation = WebasystAuthSession.shared.generation
            let gate = WebasystCompletion(completion)
            let timeout = DispatchWorkItem {
                let key = WebasystApp.getDefaultLocalizedString(withKey: "preloadTimeout")
                gate.call(.failure(WebasystError(localizedError: key,
                    underlyingErrorDomain: NSURLErrorDomain, underlyingErrorCode: NSURLErrorTimedOut)))
            }
            let complete: (WebasystResult<UserStatus>) -> Void = { result in
                timeout.cancel()
                gate.call(result)
            }
            let current: () -> Bool = {
                guard !gate.isCompleted else { return false }
                guard WebasystAuthSession.shared.isCurrent(generation) else {
                    complete(.failure(WebasystAuthFailure.make(.superseded, generation: generation).error))
                    return false
                }
                return true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
            self.downloadUserData { profileIsEmpty in
                guard current() else { return }
                self.getInstallList { result in
                    guard current() else { return }
                    switch result {
                    case .failure(let error): complete(.failure(error))
                    case .success(let installs):
                        let noInstalls: UserStatus = profileIsEmpty ? .authorizedButNoneInstallsAndProfileIsEmpty : .authorizedButNoneInstalls
                        guard !installs.isEmpty else { complete(.success(noInstalls)); return }
                        self.getAccessTokenApi(clientId: installs.map { $0.id }) { codes in
                            guard current() else { return }
                            switch codes {
                            case .failure: complete(.success(noInstalls))
                            case .success(let codes):
                                self.getAccessTokenInstall(installs, accessCodes: codes) { saved in
                                    guard current() else { return }
                                    switch saved {
                                    case .failure: complete(.success(noInstalls))
                                    case .success:
                                        UserDefaults.standard.setValue(false, forKey: "firstLaunch")
                                        complete(.success(profileIsEmpty ? .authorizedButProfileIsEmpty : .authorized))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    internal func restoreTokensFromGroup(_ completion: @escaping (Bool) -> ()) {
        let auth = WebasystAuthSession.shared
        let generation = auth.beginAuthorization()
        guard let config = WebasystApp.config,
              let url = buildWebasystUrl("/id/api/v1/auth/cross-app/", parameters: [:]),
              case .success(let token?) = KeychainManager.readToken(.accessToken, scope: .group),
              !token.isEmpty else { completion(false); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do { request.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": config.clientId]) }
        catch { completion(false); return }
        auth.requestTokens(request, generation: generation, operation: "crossApp") { result in
            switch result {
            case .success(let tokens):
                if case .success = auth.accept(tokens, generation: generation) { completion(true) }
                else { completion(false) }
            case .failure: completion(false)
            }
        }
    }
    
    // MARK: - Send Apple ID email confirmation code
    internal func sendAppleIDEmailConfirmationCode(_ code: String, accessToken: Data, _ completion: @escaping (WebasystResult<Bool>) -> ()) {
        let auth = WebasystAuthSession.shared
        let generation = auth.generation
        guard let url = buildWebasystUrl("/id/api/v1/apple/confirm/", parameters: [:]) else {
            completion(.failure(WebasystAuthFailure.make(.configuration, generation: generation).error))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(String(decoding: accessToken, as: UTF8.self), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do { request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code]) }
        catch { completion(.failure(WebasystAuthFailure.make(.configuration, generation: generation).error)); return }
        auth.requestTokens(request, generation: generation, operation: "appleEmail") { result in
            switch result {
            case .success(let tokens):
                switch auth.accept(tokens, generation: generation) {
                case .success: completion(.success(true))
                case .failure(let failure): completion(.failure(failure.error))
                }
            case .failure(let failure): completion(.failure(failure.error))
            }
        }
    }
    
    //MARK: Download user data
    internal func downloadUserData(_ completion: @escaping (Bool) -> Void) {
        let credentials = WebasystAuthSession.shared.accessCredentials
        let generation = credentials.generation
        let accessToken = credentials.token
        
        let headers: Parameters = [
            "Authorization": accessToken
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/profile/", parameters: [:]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        createDataTaskSession(request, generation: generation) { [weak self] result in
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
                        WebasystAuthSession.shared.ifCurrent(generation) {
                            self.profileInstallService?.saveProfileData(userData, avatar: data)
                        }
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
        let credentials = WebasystAuthSession.shared.accessCredentials
        let generation = credentials.generation
        let accessToken = credentials.token
        
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
        
        createDataTaskSession(request, generation: generation) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if let userData = try? JSONDecoder().decode(UserData.self, from: response.data) {
                    WebasystNetworkingManager().downloadImage(userData.userpic_original_crop) { [weak self] data in
                        guard let self = self else { return }
                        guard WebasystAuthSession.shared.isCurrent(generation) else {
                            completion(.failure(WebasystAuthFailure.make(.superseded, generation: generation).error))
                            return
                        }
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
        let credentials = WebasystAuthSession.shared.accessCredentials
        let generation = credentials.generation
        let accessToken = credentials.token
        
        let headers: Parameters = [
            "Authorization": accessToken
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/profile/userpic/", parameters: [:]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        createDataTaskSession(request, generation: generation) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                switch response.statusCode {
                case 204:
                    WebasystNetworkingManager().downloadImage(defaultImageUrl) { [weak self] data in
                        guard let self = self else { return }
                        guard WebasystAuthSession.shared.isCurrent(generation) else {
                            completion(.failure(WebasystAuthFailure.make(.superseded, generation: generation).error))
                            return
                        }
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
        let credentials = WebasystAuthSession.shared.accessCredentials
        let generation = credentials.generation
        let accessToken = credentials.token
        
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
        
        createDataTaskSession(request, generation: generation) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                switch response.statusCode {
                case 201:
                    if let json = try? JSONSerialization.jsonObject(with: response.data) as? [String : Any],
                       let original_image = json["userpic_original_crop"] as? String {
                        WebasystNetworkingManager().downloadImage(original_image) { [weak self] data in
                            guard let self = self else { return }
                            guard WebasystAuthSession.shared.isCurrent(generation) else {
                                completion(.failure(WebasystAuthFailure.make(.superseded, generation: generation).error))
                                return
                            }
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
        
        let credentials = WebasystAuthSession.shared.accessCredentials
        let generation = credentials.generation
        let accessToken = credentials.token
        
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
        
        createDataTaskSession(request, generation: generation) { [weak self] result in
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
                    deleteNonActiveInstall(installList: installList)
                    completion(.success(installList))
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
        
        let credentials = WebasystAuthSession.shared.accessCredentials
        let generation = credentials.generation
        let accessToken = credentials.token
        
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
        
        createDataTaskSession(request, generation: generation) { [weak self] result in
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
        WebasystAuthSession.onMain {
            let generation = WebasystAuthSession.shared.generation
            let gate = WebasystCompletion(completion)
            guard let config = WebasystApp.config else {
                gate.call(.failure(WebasystAuthFailure.make(.configuration, generation: generation).error))
                return
            }
            guard accessCodes["error_description"] == nil else {
                gate.call(.failure(WebasystAuthFailure.make(.server, generation: generation).error))
                return
            }
            guard !installList.isEmpty else { gate.call(.success("")); return }
            var remaining = installList.count
            let finishOne: (WebasystResult<String>) -> Void = { result in
                remaining -= 1
                if case .success = result { gate.call(result) }
                else if remaining == 0 { gate.call(result) }
            }
            for install in installList {
                guard let code = accessCodes[install.id] as? String,
                      let url = URL(string: "\(install.url)/api.php/token-headless"),
                      url.scheme == "https" || url.scheme == "http" else {
                    finishOne(.failure(WebasystAuthFailure.make(.decoding, generation: generation).error))
                    continue
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                do {
                    try request.setMultipartFormData(["code": code,
                        "scope": config.scope.replacingOccurrences(of: ".", with: ","),
                        "client_id": config.bundleId], encoding: .utf8)
                } catch {
                    finishOne(.failure(WebasystAuthFailure.make(.configuration, generation: generation).error))
                    continue
                }
                self.createDataTaskSession(request, generation: generation) { result in
                    guard WebasystAuthSession.shared.isCurrent(generation) else {
                        finishOne(.failure(WebasystAuthFailure.make(.superseded, generation: generation).error))
                        return
                    }
                    switch result {
                    case .failure(let error): finishOne(.failure(error))
                    case .success(let response):
                        guard let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: String],
                              let accessToken = json["access_token"], !accessToken.isEmpty else {
                            finishOne(.failure(WebasystAuthFailure.make(.decoding, generation: generation).error))
                            return
                        }
                        let value = UserInstallCodable(name: "", domain: install.domain, id: install.id,
                            accessToken: accessToken, url: install.url, cloudPlanId: install.cloudPlanId,
                            cloudExpireDate: install.cloudExpireDate, cloudTrial: install.cloudTrial)
                        if let active = UserDefaults.standard.string(forKey: "selectDomainUser"),
                           WebasystApp().getUserInstall(active) == nil {
                            UserDefaults.standard.setValue(install.id, forKey: "selectDomainUser")
                        }
                        self.getInstallInfo(value) { success in
                            if success { finishOne(.success(accessToken)) }
                            else { finishOne(.failure(WebasystAuthFailure.make(.superseded, generation: generation).error)) }
                        }
                    }
                }
            }
        }
    }
    
    func getInstallInfo(_ install: UserInstallCodable, loadSucces: @escaping (Bool) -> ()) {
        let generation = WebasystAuthSession.shared.generation
        let gate = WebasystCompletion(loadSucces)
        guard let url = URL(string: "\(install.url)/api.php/webasyst.getInfo?access_token=\(install.accessToken ?? "")&format=json") else {
            gate.call(false)
            return
        }
        let save: (InstallInfo?, Data?, Bool) -> Void = { info, image, imageLogo in
            let saved = WebasystAuthSession.shared.ifCurrent(generation) {
                let value = UserInstall(name: info?.name ?? install.domain, domain: install.domain,
                    id: install.id, accessToken: install.accessToken, url: install.url,
                    image: image, imageLogo: imageLogo, logoText: imageLogo ? "" : info?.logo?.text.value ?? "",
                    logoTextColor: imageLogo ? "" : info?.logo?.text.color ?? "",
                    cloudPlanId: install.cloudPlanId, cloudExpireDate: install.cloudExpireDate, cloudTrial: install.cloudTrial)
                self.profileInstallService?.saveInstall(value)
                self.profileInstallService?.createNew()
            }
            gate.call(saved)
        }
        createDataTaskSession(URLRequest(url: url), generation: generation) { result in
            guard WebasystAuthSession.shared.isCurrent(generation) else { gate.call(false); return }
            guard case .success(let response) = result,
                  let info = try? JSONDecoder().decode(InstallInfo.self, from: response.data) else {
                save(nil, self.createDefaultGradient(), false)
                return
            }
            switch info.logo?.mode {
            case .image?:
                guard let logo = try? JSONDecoder().decode(LogoImage.self, from: response.data) else {
                    save(info, self.createDefaultGradient(), false)
                    return
                }
                self.downloadImage(logo.logo?.image.thumbs.first?.value.url ?? "") { image in
                    save(info, image.isEmpty ? self.createDefaultGradient() : image, !image.isEmpty)
                }
            case .gradient?:
                let logo = try? JSONDecoder().decode(LogoGradient.self, from: response.data)
                let image = self.createGradient(from: logo?.logo?.gradient.from ?? "#FF0078",
                                                to: logo?.logo?.gradient.to ?? "#FF5900")
                save(info, image, false)
            default: save(info, self.createDefaultGradient(), false)
            }
        }
    }
    
    func createWebasystAccount(bundle: String, plainId: String, accountDomain: String?, accountName: String?, _ completion: @escaping (WebasystResult<(id: String, url: String)>) -> ()) {
        
        let credentials = WebasystAuthSession.shared.accessCredentials
        let generation = credentials.generation
        let accessToken = credentials.token
        
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
        
        createDataTaskSession(request, generation: generation) { [weak self] result in
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
        
        let credentials = WebasystAuthSession.shared.accessCredentials
        let generation = credentials.generation
        let accessToken = credentials.token
        
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
        
        createDataTaskSession(request, generation: generation) { [weak self] result in
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
        let credentials = WebasystAuthSession.shared.accessCredentials
        let generation = credentials.generation
        let accessToken = credentials.token
        
        let headerRequest: Parameters = [
            "Authorization": accessToken
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/delete/", parameters: [:]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(headerRequest.first?.value ?? "", forHTTPHeaderField: headerRequest.first?.key ?? "")
        
        createDataTaskSession(request, generation: generation) { [weak self] result in
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
        let generation = WebasystAuthSession.shared.generation
        
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
        
        createDataTaskSession(request, generation: generation) { [weak self] result in
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
        
        let credentials = WebasystAuthSession.shared.accessCredentials
        let generation = credentials.generation
        let accessToken = credentials.token
        
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
        
        createDataTaskSession(request, generation: generation) { [weak self] result in
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
        
        let credentials = WebasystAuthSession.shared.accessCredentials
        let generation = credentials.generation
        let accessToken = credentials.token
        
        let parameters: Parameters = [
            "Authorization": accessToken
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        for (key, value) in parameters {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        createDataTaskSession(request, generation: generation) { [weak self] result in
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
        
        let credentials = WebasystAuthSession.shared.accessCredentials
        let generation = credentials.generation
        let accessToken = credentials.token
        
        let parameters: Parameters = [
            "Authorization": accessToken
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        for (key, value) in parameters {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        createDataTaskSession(request, generation: generation) { [weak self] result in
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
        
        let credentials = WebasystAuthSession.shared.accessCredentials
        let generation = credentials.generation
        let accessToken = credentials.token
        
        let parameters: Parameters = [
            "Authorization": accessToken
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        for (key, value) in parameters {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        createDataTaskSession(request, generation: generation) { [weak self] result in
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
        
        let credentials = WebasystAuthSession.shared.accessCredentials
        let generation = credentials.generation
        let accessToken = credentials.token
        
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
        
        createDataTaskSession(request, generation: generation) { [weak self] result in
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
