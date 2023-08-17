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
    
}
