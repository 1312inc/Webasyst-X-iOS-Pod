//
//  WebasystNetworking.swift
//  Webasyst iOS
//
//  Created by Леонид Лукашевич on 14.08.2023.
//

import UIKit

extension WebasystNetworking {
    
    func getDeviceId() -> String {
        UIDevice.current.identifierForVendor!.uuidString
    }
}
