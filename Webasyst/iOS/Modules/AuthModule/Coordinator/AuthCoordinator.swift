//
//  AuthWebCoordinator.swift
//  WebXApp
//
//  Created by Виктор Кобыхно on 1/13/21.
//

import UIKit

public class AuthCoordinator: Coordinator, AuthCoordinatorProtocol {
    
    private unowned var navigationController: UINavigationController
    var action: ((_ result: WebasystServerAnswer) -> Void)!
    
    required init(_ navigationController: UINavigationController, action: @escaping (WebasystServerAnswer) -> ()) {
        self.navigationController = navigationController
        self.action = action
    }
    
    public func start(with code: String = "") {
        let authViewController = AuthViewController()
        let networkingService = WebasystNetworking()
        let authViewModel = AuthViewModel(networkingService: networkingService,
                                          delegate: self,
                                          with: code)
        authViewController.viewModel = authViewModel
        authViewController.modalPresentationCapturesStatusBarAppearance = true
        self.navigationController.present(authViewController, animated: true, completion: nil)
    }
}

extension AuthCoordinator: AuthCoordinatorDelegate {
    
    func successAuth(_ status: UserStatus) {
        DispatchQueue.main.async {
            self.action(.success(status))
        }
    }
    
    func errorAuth(_ error: String) {
        DispatchQueue.main.async {
            self.action(.error(error))
        }
    }
}
