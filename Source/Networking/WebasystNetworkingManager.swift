//
//  WebasystNetworkingManager.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 13.05.2021.
//

import Foundation

internal class WebasystNetworkingManager {
    
    private var config = WebasystApp.config
    
    //MARK: Build URL Webasyst Auth
    public func buildWebasystUrl(_ path: String, parameters: [String: String]) -> URL? {
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
    
    private func getData(from url: URL, completion: @escaping (Data?, URLResponse?, Error?) -> ()) {
        URLSession.shared.dataTask(with: url, completionHandler: completion).resume()
    }
    
    internal func downloadImage(_ imagePath: String, completion: @escaping (Data) -> ()) {
        getData(from: URL(string: imagePath)!) { data, response, error in
            guard let data = data, error == nil else { return }
            DispatchQueue.main.async() {
                completion(data)
            }
        }
    }
    
}
