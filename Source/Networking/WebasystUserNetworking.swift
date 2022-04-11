//
//  WebasystUserNetworking.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 17.05.2021.
//

import Foundation

final class WebasystUserNetworking: WebasystNetworkingManager {
    
    private let profileInstallService = WebasystDataModel()
    private let webasystNetworkingService = WebasystNetworking()
    private let networkingHelper = NetworkingHelper()
    private let dispatchGroup = DispatchGroup()
    private let config = WebasystApp.config
    private lazy var queue = DispatchQueue(label: "\(config?.bundleId ?? "com.webasyst.x").WebasystUserNetworkingService", qos: .userInitiated)
    static var installsIsEmpty = "Empty install list"
    
    func preloadUserData(completion: @escaping (String, Int, Bool) -> ()) {
        if self.networkingHelper.isConnectedToNetwork() {
            self.queue.async {
                self.downloadUserData()
            }
            self.dispatchGroup.notify(queue: self.queue) {
                self.getInstallList { installList in
                    guard let installs = installList else {
                        return
                    }
                    guard !installs.isEmpty else {
                        completion(WebasystUserNetworking.installsIsEmpty, 30, true)
                        return
                    }
                    var clientId: [String] = []
                    for install in installs {
                        clientId.append(install.id)
                    }
                    self.getAccessTokenApi(clientId: clientId) { (success, accessToken) in
                        if success {
                            guard let token = accessToken else {
                                return
                            }
                            self.getAccessTokenInstall(installs, accessCodes: token) { (loadText, saveSuccess) in
                                completion(loadText, 30, saveSuccess)
                            }
                        } else {
                            print(NSError(domain: "Webasyst error: error in obtaining installation tokens", code: 400, userInfo: nil))
                        }
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
                        WebasystNetworkingManager().downloadImage(userData.userpic_original_crop) { data in
                            WebasystDataModel()?.saveProfileData(userData, avatar: data)
                        }
                    }
                default:
                    print(NSError(domain: "Webasyst error: user data upload error", code: 400, userInfo: nil))
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
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    if let data = data {
                        let installList = try! JSONDecoder().decode([UserInstallCodable].self, from: data)
                        let activeInstall = UserDefaults.standard.string(forKey: "selectDomainUser")
                        if activeInstall == nil {
                            UserDefaults.standard.setValue(installList.first?.id ?? "", forKey: "selectDomainUser")
                        }
                        completion(installList)
                        self.deleteNonActiveInstall(installList: installList)
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
        } catch let error {
            print(NSError(domain: "Webasyst error: \(error.localizedDescription)", code: 400, userInfo: nil))
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
                print(NSError(domain: "Webasyst error: \(error.localizedDescription)", code: 400, userInfo: nil))
            }
        }.resume()
    }
    
    func getAccessTokenInstall(_ installList: [UserInstallCodable], accessCodes: [String: Any], completion: @escaping (String, Bool) -> ()) {
        
        guard let config = WebasystApp.config else { return }
        
        for index in 0 ..< installList.count {
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
            
            URLSession.shared.dataTask(with: request) { (data, response, error) in
                guard error == nil else {
                    return
                }
                
                guard let data = data else {
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? Parameters {
                        let installToken = UserInstallCodable(name: "", domain: installList[index].domain, id: installList[index].id, accessToken: json["access_token"]  ?? "", url: installList[index].url, cloudPlanId: installList[index].cloudPlanId, cloudExpireDate: installList[index].cloudExpireDate, cloudTrial: installList[index].cloudTrial)
                        self.getInstallInfo(installToken) { _ in
                            if index == 0 {
                                completion("\(NSLocalizedString("loadingInstallMessage", comment: ""))", true)
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
                    let imageData = self.createDefaultGradient()
                    let newInstall = UserInstall(name: info.name, domain: install.domain , id: install.id , accessToken: install.accessToken, url: install.url, image: imageData, imageLogo: false, logoText: info.logo?.text.value ?? "", logoTextColor: info.logo?.text.color ?? "", cloudPlanId: install.cloudPlanId, cloudExpireDate: install.cloudExpireDate, cloudTrial: install.cloudTrial)
                    self.profileInstallService?.saveInstall(newInstall)
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
                        loadSucces(true)
                    } catch let error {
                        print(NSError(domain: "Webasyst error: \(info.name) \(error.localizedDescription)", code: 401, userInfo: nil))
                    }
                case .unknown(value: _):
                    let imageData = self.createDefaultGradient()
                    
                    let newInstall = UserInstall(name: info.name, domain: install.domain , id: install.id , accessToken: install.accessToken, url: install.url, image: imageData, imageLogo: false, logoText: info.logo?.text.value ?? "", logoTextColor: info.logo?.text.color ?? "", cloudPlanId: install.cloudPlanId, cloudExpireDate: install.cloudExpireDate, cloudTrial: install.cloudTrial)
                    
                    self.profileInstallService?.saveInstall(newInstall)
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
    
    func createWebasystAccount(completion: @escaping (Bool, String?)->()) {
        
        let accessToken = KeychainManager.load(key: "accessToken")
        let accessTokenString = String(decoding: accessToken ?? Data("".utf8), as: UTF8.self)
        
        let headers: Parameters = [
            "Authorization": accessTokenString
        ]
        
        let parametersRequest: Parameters = [
            "bundle": "allwebasyst"
        ]
        
        guard let url = buildWebasystUrl("/id/api/v1/cloud/signup/", parameters: [:]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        do {
            try request.setMultipartFormData(parametersRequest, encoding: String.Encoding.utf8)
        } catch let error {
            completion(false, nil)
            print(NSError(domain: "Webasyst error: \(error.localizedDescription)", code: 401, userInfo: nil))
        }
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            
            if let error = error {
                print(NSError(domain: "Webasyst error: \(error.localizedDescription)", code: 401, userInfo: nil))
                completion(false, nil)
                return
            }
            
            guard let data = data else {
                print(NSError(domain: "Webasyst error: no response data", code: 401, userInfo: nil))
                completion(false, nil)
                return
            }
            
            do {
                let json = try JSONDecoder().decode(CreateNewAccount.self, from: data)
                var newInstall: [UserInstallCodable] = []
                self.getAccessTokenApi(clientId: [json.id]) { success, accessCode in
                    if success {
                        newInstall.append(UserInstallCodable(name: nil, domain: json.domain, id: json.id, accessToken: nil, url: json.url, image: nil))
                        self.getAccessTokenInstall(newInstall, accessCodes: accessCode ?? [:]) { _, success in
                            completion(true, json.url)
                        }
                    }
                }
            } catch let error {
                completion(false, nil)
                print(NSError(domain: "Webasyst error: \(error.localizedDescription)", code: 401, userInfo: nil))
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
        
        guard let saveInstalls = WebasystDataModel()?.getInstallList() else {
            return
        }
        
        var deleteInstall: [UserInstallCodable] = []
        
        for _ in installList {
            for isntall in saveInstalls {
                if !installList.contains(where: { $0.id == isntall.id }) {
                    let install = UserInstallCodable(name: isntall.name ?? "", domain: isntall.domain, id: isntall.id, accessToken: nil, url: isntall.url, image: nil)
                    deleteInstall.append(install)
                }
            }
        }
        
        for delete in deleteInstall {
            WebasystDataModel()?.deleteInstall(clientId: delete.id)
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
