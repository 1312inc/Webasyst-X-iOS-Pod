//
//  String.swift
//  Webasyst
//
//  Created by Леонид Лукашевич on 30.09.2023.
//

import Foundation

extension String {
    
    func replace(target: String, withString: String) -> String {
        return self.replacingOccurrences(of: target, with: withString, options: NSString.CompareOptions.literal, range: nil)
    }
}

extension String: Error {}
