//
//  NetworkingHelper.swift
//  Webasyst iOS
//
//  Created by Леонид Лукашевич on 14.08.2023.
//

import Network

class NetworkingHelper {
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            if path.status == .satisfied {
                isConnectedToNetwork = true
            } else {
                isConnectedToNetwork = false
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkConnectivityMonitor")
    private(set) var isConnectedToNetwork: Bool = true
}
