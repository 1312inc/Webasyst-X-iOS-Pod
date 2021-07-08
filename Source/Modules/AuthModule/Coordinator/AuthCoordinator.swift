//
//  AuthWebCoordinator.swift
//  WebXApp
//
//  Created by Виктор Кобыхно on 1/13/21.
//

import UIKit

protocol AuthCoordinatorProtocol {
    init(_ navigationController: UINavigationController)
}

public enum WebasystServerAnswer {
    case success
    case error(error: String)
}

protocol AuthCoordinatorDelegate {
    func successAuth()
    func errorAuth()
}


protocol Coordinator: AnyObject {
    var childCoordinator: [Coordinator] { get }
    func start()
}

public class AuthCoordinator: Coordinator, AuthCoordinatorDelegate, AuthCoordinatorProtocol {
    
    private var navigationController: UINavigationController
    
    var action: ((_ result: WebasystServerAnswer) -> Void)!
    
    public required init(_ navigationController: UINavigationController) {
        self.navigationController = navigationController
    }
    
    private(set) var childCoordinator: [Coordinator] = []
    
    public func start() {
        let authViewController = AuthViewController()
        let authCoordinator = AuthCoordinator(self.navigationController)
        let networkingService = WebasystNetworking()
        let authViewModel = AuthViewModel(networkingService: networkingService, coordinator: authCoordinator)
        authViewModel.delegate = self
        authViewController.viewModel = authViewModel
        self.navigationController.present(authViewController, animated: true, completion: nil)
    }
    
    func successAuth() {
        DispatchQueue.main.async {
            self.navigationController.dismiss(animated: true, completion: nil)
            self.action(WebasystServerAnswer.success)
        }
    }
    
    func errorAuth() {
        DispatchQueue.main.async {
            self.navigationController.dismiss(animated: true, completion: nil)
            self.action(WebasystServerAnswer.error(error: "Undefined error"))
        }
    }
    
}
