//
//  NetworkingHelper.swift
//  Webasyst iOS
//
//  Created by Леонид Лукашевич on 14.08.2023.
//

import Network

final class NetworkingHelper {
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            if path.status == .satisfied {
                isConnectedToNetwork = true
            } else {
                isConnectedToNetwork = false
            }
        }
    }
    
    private let monitor = NWPathMonitor()
    private(set) var isConnectedToNetwork: Bool = false
}
