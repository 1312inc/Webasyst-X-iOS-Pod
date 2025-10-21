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
        
        let navigationController = UINavigationController(rootViewController: authViewController)
        
        navigationController.modalPresentationCapturesStatusBarAppearance = true
        navigationController.modalPresentationStyle = .pageSheet
        
        let closeItem: UIBarButtonItem
        
        if #available(iOS 14.0, *) {
            closeItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.close() })
        } else {
            closeItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        }
        
        authViewController.navigationItem.setRightBarButton(closeItem, animated: true)
        
        self.navigationController.present(navigationController, animated: true, completion: nil)
    }
}

extension AuthCoordinator: AuthCoordinatorDelegate {
    
    func successAuth(_ status: UserStatus) {
        DispatchQueue.main.async {
            self.action(.success(status))
        }
    }
    
    func errorAuth(_ error: WebasystError) {
        DispatchQueue.main.async {
            self.action(.error(error))
        }
    }
}

@objc private
extension AuthCoordinator {
    
    func close() {
        navigationController.dismiss(animated: true)
    }
}
