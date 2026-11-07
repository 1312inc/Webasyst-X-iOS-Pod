//
//  WebasystNetworkingManager.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 13.05.2021.
//

import Foundation

public class WebasystNetworkingManager {
    internal static var session = URLSession.shared
    
    /// Build URL Webasyst Auth
    /// - Parameters:
    ///   - path: query path excluding domain
    ///   - parameters: Request url parameters
    /// - Returns: optional URL
    public func buildWebasystUrl(_ path: String, parameters: Parameters) -> URL? {
        if let config = WebasystApp.config {
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
            return urlComponents?.absoluteURL
        }
        return nil
    }
    
    
    
    /// Image upload request
    /// - Parameters:
    ///   - url: Url image
    ///   - completion: Short-circuiting after an image has been loaded
    private func getData(from url: URL, completion: @escaping (Data?, URLResponse?, Error?) -> ()) {
        Self.session.dataTask(with: url, completionHandler: completion).resume()
    }
    
    /// The method of loading an image
    /// - Parameters:
    ///   - imagePath: Url image
    ///   - completion: Closing performed after loading the image
    /// - Returns: Data format image
    internal func downloadImage(_ imagePath: String, completion: @escaping (Data) -> ()) {
        guard let url = URL(string: imagePath), url.scheme == "https" || url.scheme == "http" else {
            completion(Data())
            return
        }
        let generation = WebasystAuthSession.shared.generation
        getData(from: url) { data, response, error in
            DispatchQueue.main.async() {
                guard WebasystAuthSession.shared.isCurrent(generation) else { completion(Data()); return }
                completion(error == nil ? data ?? Data() : Data())
            }
        }
    }
    
    internal func createDataTaskSession(_ request: URLRequest, generation: UInt64,
                                       _ completion: @escaping (WebasystResult<ServerResponse>) -> ()) {
        let deliver: (WebasystResult<ServerResponse>) -> Void = { result in
            DispatchQueue.main.async {
                guard WebasystAuthSession.shared.isCurrent(generation) else {
                    completion(.failure(WebasystAuthFailure.make(.superseded, generation: generation).error))
                    return
                }
                completion(result)
            }
        }
        Self.session.dataTask(with: request) { data, response, error in
            if let error = error as NSError? {
                let status = (response as? HTTPURLResponse)?.statusCode
                let failure = WebasystAuthFailure.make(.transport, generation: generation, status: status,
                    code: error.code, domain: error.domain)
                WebasystAuthDiagnostics.record("request", outcome: "failed", failure: failure)
                deliver(.failure(failure.error))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                let localizedError = WebasystApp.getDefaultLocalizedString(withKey: "unownedStatusCode", comment: "Unowned server response status code")
                let error = WebasystError(localizedError: localizedError)
                
                deliver(.failure(error))
                
                return
            }
            
            let statusCode = response.statusCode
            
            guard let data = data else {
                let localizedError = WebasystApp.getDefaultLocalizedString(withKey: "emptyResponsedData", comment: "Empty responsed data")
                let error = WebasystError(localizedError: localizedError, statusCode: statusCode)
                
                deliver(.failure(error))
                
                return
            }
            
            switch statusCode {
            case 200...299:
                let serverResponse = ServerResponse(data: data, response: response, statusCode: response.statusCode)
                deliver(.success(serverResponse))
            case 400...504:
                do {
                    let errorModel = try JSONDecoder().decode(ErrorModel.self, from: data)
                    
                    switch statusCode {
                    case 401:
                        let localizedError = WebasystApp.getDefaultLocalizedString(withKey: "missingAuthToken", comment: "The authentication token is missing.")
                        let error = WebasystError(localizedError: localizedError, statusCode: statusCode, errorValue: errorModel.error)
                        
                        deliver(.failure(error))
                    case 404:
                        let localizedError = WebasystApp.getDefaultLocalizedString(withKey: "404Error", comment: "Server send 404 error")
                        let error = WebasystError(localizedError: localizedError, statusCode: statusCode, errorValue: errorModel.error)
                        
                        deliver(.failure(error))
                    default:
                        if let error = errorModel.errorDescription, !error.isEmpty {
                            let localizedErrorString = WebasystApp.getDefaultLocalizedString(withKey: "network.error.description")
                            let localizedError = localizedErrorString.replacingOccurrences(of: "%ERROR%", with: error)
                            let error = WebasystError(localizedError: localizedError, statusCode: statusCode, errorValue: errorModel.error)
                            
                            deliver(.failure(error))
                        } else if let error = errorModel.error, !error.isEmpty {
                            let localizedErrorString = WebasystApp.getDefaultLocalizedString(withKey: "network.error.value")
                            let localizedError = localizedErrorString.replacingOccurrences(of: "%ERROR%", with: error)
                            let error = WebasystError(localizedError: localizedError, statusCode: statusCode, errorValue: error)
                            
                            deliver(.failure(error))
                        } else {
                            let localizedErrorString = WebasystApp.getDefaultLocalizedString(withKey: "unownedErrorWithStatusCode", comment: "Unowned error with response status code")
                            let localizedError = localizedErrorString.replacingOccurrences(of: "%CODE%", with: statusCode.description)
                            let error = WebasystError(localizedError: localizedError, statusCode: statusCode, errorValue: errorModel.error)
                            
                            deliver(.failure(error))
                        }
                    }
                } catch let error {
                    let localizedErrorString = WebasystApp.getDefaultLocalizedString(withKey: "unownedErrorWithStatusCode", comment: "Unowned error with response status code")
                    let localizedError = localizedErrorString.replacingOccurrences(of: "%CODE%", with: statusCode.description) + " " + error.localizedDescription
                    let error = WebasystError(localizedError: localizedError, statusCode: statusCode)
                    
                    deliver(.failure(error))
                }
            default:
                let localizedErrorString = WebasystApp.getDefaultLocalizedString(withKey: "unownedErrorWithStatusCode", comment: "Unowned error with response status code")
                let localizedError = localizedErrorString.replacingOccurrences(of: "%CODE%", with: statusCode.description)
                let error = WebasystError(localizedError: localizedError, statusCode: statusCode)
                
                deliver(.failure(error))
            }
        }
        .resume()
    }
    
    internal func getError(_ model: ErrorTypeModel) -> WebasystError {
        WebasystError.getError(model)
    }
}
