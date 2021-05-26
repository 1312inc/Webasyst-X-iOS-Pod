//
//  AuthViewModel.swift
//  WebXApp
//
//  Created by Виктор Кобыхно on 1/13/21.
//

import Foundation

protocol AuthViewModelProtocol: AnyObject {
    var authRequest: URLRequest? { get }
    init(networkingService: WebasystNetworking, coordinator: AuthCoordinatorProtocol)
    func successAuth(code: String, state: String)
}

final class AuthViewModel: AuthViewModelProtocol {
    
    private var networkingService: WebasystNetworking
    private var coordinator: AuthCoordinatorProtocol
    var authRequest: URLRequest?
    var delegate: AuthCoordinatorDelegate!
    
    init(networkingService: WebasystNetworking, coordinator: AuthCoordinatorProtocol) {
        self.networkingService = networkingService
        self.authRequest = networkingService.buildAuthRequest()
        self.coordinator = coordinator
    }
    
    func successAuth(code: String, state: String) {
        networkingService.getAccessToken(code, stateString: state) { success in
            DispatchQueue.main.async {
                if success {
                    self.delegate.successAuth()
                } else {
                    self.delegate.errorAuth()
                }
            }
        }
        
    }
    
}
