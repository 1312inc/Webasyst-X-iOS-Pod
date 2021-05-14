//
//  Webasyst.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 12.05.2021.
//

import UIKit

public class WebasystApp {
    
    internal static var config: WebasystConfig?
    
    public init() {}
    
    public static func configure(bundleId: String) {
        config = WebasystConfig(bundleId: bundleId)
    }
    
    public static func authWebasyst(navigationController: UINavigationController, action: @escaping ((_ result: WebasystServerAnswer) -> ())) {
        let coordinator = AuthCoordinator(navigationController)
        coordinator.start()
        let success: ((_ action: WebasystServerAnswer) -> Void) = { success in
            switch success {
            case .success:
                action(WebasystServerAnswer.success)
            case .error(error: let error):
                action(WebasystServerAnswer.error(error: error))
            }
        }
        coordinator.action = success
    }
    
}
