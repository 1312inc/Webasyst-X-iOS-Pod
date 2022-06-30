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

protocol AuthCoordinatorDelegate: AnyObject {
    func successAuth()
    func listOrProfileIsEmpty(_ status: UserStatus)
    func errorAuth()
}


protocol Coordinator: AnyObject {
    func start(with code: String)
}

public class AuthCoordinator: Coordinator, AuthCoordinatorDelegate, AuthCoordinatorProtocol {
    
    private var navigationController: UINavigationController
    
    var action: ((_ result: WebasystServerAnswer) -> Void)!
    
    public required init(_ navigationController: UINavigationController) {
        self.navigationController = navigationController
    }
        
    public func start(with code: String = "") {
        let authViewController = AuthViewController()
        let authCoordinator = AuthCoordinator(self.navigationController)
        let networkingService = WebasystNetworking()
        let authViewModel = AuthViewModel(networkingService: networkingService,
                                          coordinator: authCoordinator,
                                          with: code)
        authViewModel.delegate = self
        authViewController.viewModel = authViewModel
        self.navigationController.present(authViewController, animated: true, completion: nil)
    }
    
    func successAuth() {
        DispatchQueue.main.async {
            self.action(WebasystServerAnswer.success)
        }
    }
    
    func listOrProfileIsEmpty(_ status: UserStatus) {
        DispatchQueue.main.async {
            self.action(.success)
        }
    }
    
    func errorAuth() {
        DispatchQueue.main.async {
            self.action(WebasystServerAnswer.error(error: "Undefined error"))
        }
    }
    
}
