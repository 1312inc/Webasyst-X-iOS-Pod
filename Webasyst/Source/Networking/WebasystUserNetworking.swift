//
//  WebasystUserNetworking.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 17.05.2021.
//

import UIKit

enum WebasystInstallationExchangeResult {
    case success(UserInstall)
    case codeRequestFailed(WebasystError)
    case failure(WebasystError)
}

// Owned by one authorization generation and accessed on the main queue.
final class WebasystInstallationState {
    final class Exchange {
        let installation: UserInstallCodable
        var callbacks: [(WebasystInstallationExchangeResult) -> Void] = []

        init(installation: UserInstallCodable) {
            self.installation = installation
        }
    }

    var catalog: [UserInstallCodable]?
    var catalogRequestNumber = 0
    var lastAppliedCatalogRequest = 0
    var exchanges: [String: Exchange] = [:]
    var needsExplicitSelection = false
    var excludedInstallations: Set<String> = []
    private var notificationPending = false

    func notifyChanged() {
        guard !notificationPending else { return }
        notificationPending = true
        DispatchQueue.main.async {
            self.notificationPending = false
            guard WebasystAuthSession.shared.installations === self else { return }
            NotificationCenter.default.post(name: .webasystInstallationsDidChange, object: nil)
        }
    }
}

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
            var catalogLoadedStatus: UserStatus?
            let timeout = DispatchWorkItem {
                if WebasystAuthSession.shared.isCurrent(generation), let catalogLoadedStatus {
                    gate.call(.success(catalogLoadedStatus))
                    return
                }
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
                        catalogLoadedStatus = noInstalls
                        self.refreshInstallationAccess(installs) { result in
                            guard current() else { return }
                            switch result {
                            case .success:
                                let key = UserDefaultsKeys.selectDomainUser.rawValue
                                let active = UserDefaults.standard.string(forKey: key) ?? ""
                                let cached = self.profileInstallService?.getInstall(with: active)
                                if cached?.accessToken?.isEmpty == false,
                                   !WebasystAuthSession.shared.installations.excludedInstallations.contains(active) {
                                    UserDefaults.standard.setValue(false, forKey: "firstLaunch")
                                    complete(.success(profileIsEmpty ? .authorizedButProfileIsEmpty : .authorized))
                                } else {
                                    complete(.success(noInstalls))
                                }
                            case .codeRequestFailed, .failure:
                                complete(.success(noInstalls))
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
    func getInstallList(_ completion: @escaping (WebasystResult<[UserInstallCodable]>) -> Void) {
        let auth = WebasystAuthSession.shared
        let (credentials, state, requestNumber) = WebasystAuthSession.onMain {
            let credentials = auth.accessCredentials
            let state = auth.installations
            state.catalogRequestNumber += 1
            return (credentials, state, state.catalogRequestNumber)
        }
        guard let url = buildWebasystUrl("/id/api/v1/installations/", parameters: [:]) else {
            completion(.failure(WebasystAuthFailure.make(.configuration, generation: credentials.generation).error))
            return
        }
        var request = URLRequest(url: url)
        request.setValue(credentials.token, forHTTPHeaderField: "Authorization")
        createDataTaskSession(request, generation: credentials.generation) { result in
            switch result {
            case .success(let response):
                guard requestNumber > state.lastAppliedCatalogRequest else {
                    completion(.success(state.catalog ?? []))
                    return
                }
                do {
                    let decoded = try JSONDecoder().decode([UserInstallCodable].self, from: response.data)
                    let installs = decoded.map { entry in
                        var metadata = entry
                        metadata.accessToken = nil
                        return metadata
                    }
                    let urls = Dictionary(installs.map { ($0.id, $0.url) }, uniquingKeysWith: { first, _ in first })
                    state.lastAppliedCatalogRequest = requestNumber
                    state.catalog = installs
                    state.excludedInstallations.subtract(urls.keys)
                    self.deleteNonActiveInstalls(urls: urls)
                    self.reconcileActiveInstallation()
                    for flight in Array(state.exchanges.values) where urls[flight.installation.id] != flight.installation.url {
                        let error = WebasystAuthFailure.make(.superseded, generation: credentials.generation).error
                        self.finishExchange(flight, in: state, result: .failure(error))
                    }
                    state.notifyChanged()
                    completion(.success(installs))
                } catch {
                    completion(.failure(WebasystAuthFailure.make(.decoding, generation: credentials.generation,
                                                                 status: response.statusCode).error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func getAccessTokenApi(clientId: [String], timeout: TimeInterval = 60, _ completion: @escaping (WebasystResult<[String : Any]>) -> ()) {
        
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
        
        var request = URLRequest(url: url, timeoutInterval: timeout)
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
    
    // The batch keeps its first-success completion for login and legacy clients.
    // Every installation still publishes its own result to the catalog.
    func refreshInstallationAccess(_ installs: [UserInstallCodable], manual: Bool = false,
                                   completion: @escaping (WebasystInstallationExchangeResult) -> Void) {
        let auth = WebasystAuthSession.shared
        let state = auth.installations
        let generation = auth.generation
        if manual {
            let key = UserDefaultsKeys.selectDomainUser.rawValue
            if UserDefaults.standard.string(forKey: key)?.isEmpty != false {
                state.needsExplicitSelection = true
            }
        }
        let gate = WebasystCompletion(completion)
        var remaining = installs.count
        let finishOne: (WebasystInstallationExchangeResult) -> Void = { result in
            remaining -= 1
            if case .success = result { gate.call(result) }
            else if remaining == 0 { gate.call(result) }
        }
        var newFlights: [WebasystInstallationState.Exchange] = []
        for install in installs {
            guard state.catalog?.contains(where: { $0.id == install.id && $0.url == install.url }) == true else {
                finishOne(.failure(WebasystAuthFailure.make(.superseded, generation: generation).error))
                continue
            }
            if let flight = state.exchanges[install.id] {
                flight.callbacks.append(finishOne)
            } else {
                let flight = WebasystInstallationState.Exchange(installation: install)
                flight.callbacks = [finishOne]
                state.exchanges[install.id] = flight
                newFlights.append(flight)
            }
        }
        guard !newFlights.isEmpty else { return }
        state.notifyChanged()
        let timeout: TimeInterval = manual ? 15 : 60
        getAccessTokenApi(clientId: newFlights.map { $0.installation.id }, timeout: timeout) { result in
            for flight in newFlights where state.exchanges[flight.installation.id] === flight {
                switch result {
                case .failure(let error):
                    self.finishExchange(flight, in: state, result: .codeRequestFailed(error))
                case .success(let codes):
                    let install = flight.installation
                    guard let code = codes[install.id] as? String, !code.isEmpty, codes["error_description"] == nil else {
                        let error = WebasystAuthFailure.make(.decoding, generation: generation).error
                        self.finishExchange(flight, in: state, result: .failure(error))
                        continue
                    }
                    self.exchangeInstallationToken(install, code: code, generation: generation, timeout: timeout) { result in
                        guard state.exchanges[install.id] === flight else { return }
                        switch result {
                        case .failure(let error):
                            self.finishExchange(flight, in: state, result: .failure(error))
                        case .success(let authorizedInstall):
                            guard let saved = self.saveInstallationToken(authorizedInstall) else {
                                let error = WebasystAuthFailure.make(.storage, generation: generation).error
                                self.finishExchange(flight, in: state, result: .failure(error))
                                return
                            }
                            self.reconcileActiveInstallation()
                            self.finishExchange(flight, in: state, result: .success(saved))
                            self.getInstallInfo(authorizedInstall, generation: generation, catalog: state)
                        }
                    }
                }
            }
        }
    }

    private func finishExchange(_ flight: WebasystInstallationState.Exchange, in state: WebasystInstallationState,
                                result: WebasystInstallationExchangeResult) {
        state.exchanges.removeValue(forKey: flight.installation.id)
        state.notifyChanged()
        let callbacks = flight.callbacks
        flight.callbacks.removeAll()
        DispatchQueue.main.async {
            let auth = WebasystAuthSession.shared
            for callback in callbacks {
                if auth.installations === state {
                    callback(result)
                } else {
                    callback(.failure(WebasystAuthFailure.make(.superseded, generation: auth.generation).error))
                }
            }
        }
    }

    // Account creation uses codes returned for a new installation before it appears in the WAID catalog.
    func getAccessTokenInstall(_ installList: [UserInstallCodable], accessCodes: [String: Any],
                               _ completion: @escaping (WebasystResult<String>) -> Void) {
        WebasystAuthSession.onMain {
            let generation = WebasystAuthSession.shared.generation
            guard !installList.isEmpty else { completion(.success("")); return }
            guard accessCodes["error_description"] == nil else {
                completion(.failure(WebasystAuthFailure.make(.server, generation: generation).error))
                return
            }
            let gate = WebasystCompletion(completion)
            var remaining = installList.count
            let finishOne: (WebasystResult<String>) -> Void = { result in
                remaining -= 1
                if case .success = result { gate.call(result) }
                else if remaining == 0 { gate.call(result) }
            }
            for install in installList {
                guard let code = accessCodes[install.id] as? String, !code.isEmpty else {
                    finishOne(.failure(WebasystAuthFailure.make(.decoding, generation: generation).error))
                    continue
                }
                exchangeInstallationToken(install, code: code, generation: generation, timeout: 60) { result in
                    switch result {
                    case .failure(let error): finishOne(.failure(error))
                    case .success(let authorizedInstall):
                        guard let saved = self.saveInstallationToken(authorizedInstall), let token = saved.accessToken else {
                            finishOne(.failure(WebasystAuthFailure.make(.storage, generation: generation).error))
                            return
                        }
                        self.getInstallInfo(authorizedInstall, generation: generation, catalog: nil) {
                            guard WebasystAuthSession.shared.isCurrent(generation) else {
                                finishOne(.failure(WebasystAuthFailure.make(.superseded, generation: generation).error))
                                return
                            }
                            let key = UserDefaultsKeys.selectDomainUser.rawValue
                            if let active = UserDefaults.standard.string(forKey: key),
                               self.profileInstallService?.getInstall(with: active) == nil {
                                UserDefaults.standard.set(install.id, forKey: key)
                            }
                            finishOne(.success(token))
                        }
                    }
                }
            }
        }
    }

    private func exchangeInstallationToken(_ install: UserInstallCodable, code: String, generation: UInt64,
                                           timeout: TimeInterval, completion: @escaping (WebasystResult<UserInstallCodable>) -> Void) {
        guard WebasystAuthSession.shared.isCurrent(generation) else {
            completion(.failure(WebasystAuthFailure.make(.superseded, generation: generation).error))
            return
        }
        guard let config = WebasystApp.config,
              let url = URL(string: "\(install.url)/api.php/token-headless"),
              url.scheme == "https" || url.scheme == "http", url.host != nil else {
            completion(.failure(WebasystAuthFailure.make(.configuration, generation: generation).error))
            return
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        do {
            try request.setMultipartFormData(["code": code,
                "scope": config.scope.replacingOccurrences(of: ".", with: ","),
                "client_id": config.bundleId], encoding: .utf8)
        } catch {
            completion(.failure(WebasystAuthFailure.make(.configuration, generation: generation).error))
            return
        }
        createDataTaskSession(request, generation: generation) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let response):
                guard let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
                      let token = json["access_token"] as? String, !token.isEmpty else {
                    completion(.failure(WebasystAuthFailure.make(.decoding, generation: generation,
                                                                 status: response.statusCode).error))
                    return
                }
                var authorizedInstall = install
                authorizedInstall.accessToken = token
                completion(.success(authorizedInstall))
            }
        }
    }

    private func saveInstallationToken(_ install: UserInstallCodable) -> UserInstall? {
        let cached = profileInstallService?.getInstall(with: install.id)
        let previous = cached?.url == install.url ? cached : nil
        let name = previous?.name.flatMap { $0.isEmpty ? nil : $0 }
            ?? install.name.flatMap { $0.isEmpty ? nil : $0 } ?? install.domain
        let value = UserInstall(name: name, domain: install.domain, id: install.id,
            accessToken: install.accessToken, url: install.url, image: previous?.image ?? install.image ?? createDefaultGradient(),
            imageLogo: previous?.imageLogo ?? true, logoText: previous?.logoText ?? "",
            logoTextColor: previous?.logoTextColor ?? "", cloudPlanId: install.cloudPlanId,
            cloudExpireDate: install.cloudExpireDate, cloudTrial: install.cloudTrial)
        guard profileInstallService?.saveInstall(value) == true else { return nil }
        WebasystAuthSession.shared.installations.excludedInstallations.remove(install.id)
        profileInstallService?.createNew()
        return value
    }

    private func reconcileActiveInstallation() {
        let state = WebasystAuthSession.shared.installations
        guard let catalog = state.catalog else { return }
        let key = UserDefaultsKeys.selectDomainUser.rawValue
        let active = UserDefaults.standard.string(forKey: key)
        let cached = profileInstallService?.getInstallList() ?? []
        let ready = Dictionary(cached.filter { $0.accessToken?.isEmpty == false }.map { ($0.id, $0.url) },
                               uniquingKeysWith: { first, _ in first })
        if let active, !active.isEmpty {
            // Keep the previous choice even if it is absent, so the app can ask for a new one.
            state.needsExplicitSelection = false
            return
        }
        if state.needsExplicitSelection { return }
        let next = catalog.first { ready[$0.id] == $0.url }?.id
        if active != next { UserDefaults.standard.set(next, forKey: key) }
    }

    private func getInstallInfo(_ install: UserInstallCodable, generation: UInt64, catalog: WebasystInstallationState?,
                                completion: @escaping () -> Void = {}) {
        guard WebasystAuthSession.shared.isCurrent(generation),
              var components = URLComponents(string: "\(install.url)/api.php/webasyst.getInfo") else {
            completion()
            return
        }
        components.queryItems = [URLQueryItem(name: "access_token", value: install.accessToken),
                                 URLQueryItem(name: "format", value: "json")]
        if let query = components.percentEncodedQuery {
            components.percentEncodedQuery = query.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { completion(); return }
        let save: (InstallInfo, Data?, Bool) -> Void = { info, image, imageLogo in
            defer { completion() }
            guard WebasystAuthSession.shared.isCurrent(generation),
                  catalog == nil || catalog?.catalog?.contains(where: { $0.id == install.id && $0.url == install.url }) == true,
                  var current = self.profileInstallService?.getInstall(with: install.id),
                  current.url == install.url, current.accessToken == install.accessToken else { return }
            current.name = info.name
            current.image = image
            current.imageLogo = imageLogo
            current.logoText = imageLogo ? "" : info.logo?.text.value ?? ""
            current.logoTextColor = imageLogo ? "" : info.logo?.text.color ?? ""
            if self.profileInstallService?.saveInstall(current) == true { catalog?.notifyChanged() }
        }
        createDataTaskSession(URLRequest(url: url), generation: generation) { result in
            guard case .success(let response) = result,
                  let info = try? JSONDecoder().decode(InstallInfo.self, from: response.data) else {
                completion()
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
            default:
                save(info, self.createDefaultGradient(), false)
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
    
    private func deleteNonActiveInstalls(urls: [String: String]) {
        guard let saved = profileInstallService?.getInstallList() else { return }
        for install in saved where urls[install.id] != install.url {
            WebasystAuthSession.shared.installations.excludedInstallations.insert(install.id)
            profileInstallService?.deleteInstall(clientId: install.id)
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
