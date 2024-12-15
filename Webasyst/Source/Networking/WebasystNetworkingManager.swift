//
//  WebasystNetworkingManager.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 13.05.2021.
//

import Foundation

public class WebasystNetworkingManager {
    
    private var config = WebasystApp.config
    
    /// Build URL Webasyst Auth
    /// - Parameters:
    ///   - path: query path excluding domain
    ///   - parameters: Request url parameters
    /// - Returns: optional URL
    public func buildWebasystUrl(_ path: String, parameters: Parameters) -> URL? {
        if let config = self.config {
            var urlComponents: URL? {
                var component = URLComponents()
                component.scheme = "https"
                component.host = config.host
                component.path = path
                if !parameters.isEmpty {
                    var queryParams = [URLQueryItem]()
                    for param in parameters {
                        queryParams.append(URLQueryItem(name: param.key, value: param.value))
                    }
                    component.queryItems = queryParams
                }
                return component.url
            }
            return urlComponents!.absoluteURL
        }
        return nil
    }
    
    
    
    /// Image upload request
    /// - Parameters:
    ///   - url: Url image
    ///   - completion: Short-circuiting after an image has been loaded
    private func getData(from url: URL, completion: @escaping (Data?, URLResponse?, Error?) -> ()) {
        URLSession.shared.dataTask(with: url, completionHandler: completion).resume()
    }
    
    /// The method of loading an image
    /// - Parameters:
    ///   - imagePath: Url image
    ///   - completion: Closing performed after loading the image
    /// - Returns: Data format image
    internal func downloadImage(_ imagePath: String, completion: @escaping (Data) -> ()) {
        getData(from: URL(string: imagePath)!) { data, response, error in
            guard let data = data, error == nil else { return }
            DispatchQueue.main.async() {
                completion(data)
            }
        }
    }
    
    internal func createDataTaskSession(_ request: URLRequest, _ completion: @escaping (WebasystResult<ServerResponse>) -> ()) {
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let response = response as? HTTPURLResponse else {
                let localizadError = WebasystApp.getDefaultLocalizedString(withKey: "unownedStatusCode", comment: "Unowned server response status code")
                let error = WebasystError(localizadError: localizadError)
                
                completion(.failure(error))
                
                return
            }
            
            let statusCode = response.statusCode
            
            if let error = error {
                let localizedErrorString = WebasystApp.getDefaultLocalizedString(withKey: "network.error.dataTask")
                let localizedError = localizedErrorString.replacingOccurrences(of: "%ERROR%", with: error.localizedDescription)
                let error = WebasystError(localizadError: localizedError, statusCode: statusCode)
                
                completion(.failure(error))
                
                return
            }
            
            guard let data = data else {
                let localizadError = WebasystApp.getDefaultLocalizedString(withKey: "emptyResponsedData", comment: "Empty responsed data")
                let error = WebasystError(localizadError: localizadError, statusCode: statusCode)
                
                completion(.failure(error))
                
                return
            }
            
            switch statusCode {
            case 200...299:
                let serverResponse = ServerResponse(data: data, response: response, statusCode: response.statusCode)
                completion(.success(serverResponse))
            case 400...504:
                do {
                    let errorModel = try JSONDecoder().decode(ErrorModel.self, from: data)
                    
                    switch statusCode {
                    case 401:
                        let localizadError = WebasystApp.getDefaultLocalizedString(withKey: "missingAuthToken", comment: "The authentication token is missing.")
                        let error = WebasystError(localizadError: localizadError, statusCode: statusCode, errorValue: errorModel.error)
                        
                        completion(.failure(error))
                    case 404:
                        let localizadError = WebasystApp.getDefaultLocalizedString(withKey: "404Error", comment: "Server send 404 error")
                        let error = WebasystError(localizadError: localizadError, statusCode: statusCode, errorValue: errorModel.error)
                        
                        completion(.failure(error))
                    default:
                        if let error = errorModel.errorDescription, !error.isEmpty {
                            let localizedErrorString = WebasystApp.getDefaultLocalizedString(withKey: "network.error.description")
                            let localizedError = localizedErrorString.replacingOccurrences(of: "%ERROR%", with: error)
                            let error = WebasystError(localizadError: localizedError, statusCode: statusCode, errorValue: errorModel.error)
                            
                            completion(.failure(error))
                        } else if let error = errorModel.error, !error.isEmpty {
                            let localizedErrorString = WebasystApp.getDefaultLocalizedString(withKey: "network.error.value")
                            let localizedError = localizedErrorString.replacingOccurrences(of: "%ERROR%", with: error)
                            let error = WebasystError(localizadError: localizedError, statusCode: statusCode, errorValue: error)
                            
                            completion(.failure(error))
                        } else {
                            let localizedErrorString = WebasystApp.getDefaultLocalizedString(withKey: "unownedErrorWithStatusCode", comment: "Unowned error with response status code")
                            let localizedError = localizedErrorString.replacingOccurrences(of: "%CODE%", with: statusCode.description)
                            let error = WebasystError(localizadError: localizedError, statusCode: statusCode, errorValue: errorModel.error)
                            
                            completion(.failure(error))
                        }
                    }
                } catch let error {
                    let localizedErrorString = WebasystApp.getDefaultLocalizedString(withKey: "unownedErrorWithStatusCode", comment: "Unowned error with response status code")
                    let localizedError = localizedErrorString.replacingOccurrences(of: "%CODE%", with: statusCode.description) + " " + error.localizedDescription
                    let error = WebasystError(localizadError: localizedError, statusCode: statusCode)
                    
                    completion(.failure(error))
                }
            default:
                let localizedErrorString = WebasystApp.getDefaultLocalizedString(withKey: "unownedErrorWithStatusCode", comment: "Unowned error with response status code")
                let localizedError = localizedErrorString.replacingOccurrences(of: "%CODE%", with: statusCode.description)
                let error = WebasystError(localizadError: localizedError, statusCode: statusCode)
                
                completion(.failure(error))
            }
        }
        .resume()
    }
    
    internal func getError(_ model: ErrorTypeModel) -> WebasystError {
        WebasystError.getError(model)
    }
}
