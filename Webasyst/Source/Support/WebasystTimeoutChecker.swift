//
//  WebasystTimeoutChecker.swift
//  Webasyst
//
//  Created by Леонид Лукашевич on 30.09.2023.
//

import Foundation

final class WebasystTimeoutChecker {
    
    var timer: Timer?
    
    func start(_ completion: @escaping () -> ()) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { timer in
            completion()
            timer.invalidate()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
