//
//  AuthWebCoordinator.swift
//  WebXApp
//
//  Created by Виктор Кобыхно on 1/13/21.
//

import UIKit

protocol Coordinator: AnyObject {
    func start(with code: String)
}

protocol AuthCoordinatorProtocol {
    init(_ navigationController: UINavigationController, action: @escaping (WebasystServerAnswer) -> ())
}

protocol AuthCoordinatorDelegate: AnyObject {
    func successAuth()
    func listOrProfileIsEmpty(_ status: UserStatus)
    func errorAuth()
}

public enum WebasystServerAnswer {
    case success
    case error(error: String)
}

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
        self.navigationController.present(authViewController, animated: true, completion: nil)
    }
}

extension AuthCoordinator: AuthCoordinatorDelegate {
    
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
