//
//  WebasystNetworking.swift
//  Webasyst iOS
//
//  Created by Леонид Лукашевич on 14.08.2023.
//

import WatchKit

extension WebasystNetworking {
    
    func getDeviceId() -> String {
        UserDefaults.standard.string(forKey: "deviceID") ?? WKInterfaceDevice.current().identifierForVendor!.uuidString
    }
}
