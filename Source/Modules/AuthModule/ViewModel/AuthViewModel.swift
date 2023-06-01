//
//  AuthViewModel.swift
//  WebXApp
//
//  Created by Виктор Кобыхно on 1/13/21.
//

import Foundation

protocol AuthViewModelProtocol: AnyObject {
    var authRequest: URLRequest? { get }
    init(networkingService: WebasystNetworking, delegate: AuthCoordinatorDelegate, with code: String)
    func successAuth(code: String, state: String)
}

final class AuthViewModel: AuthViewModelProtocol {
    
    private var networkingService: WebasystNetworking
    private weak var delegate: AuthCoordinatorDelegate?
    private var webAsystNetworking = WebasystUserNetworking()
    
    var authRequest: URLRequest?
    
    init(networkingService: WebasystNetworking, delegate: AuthCoordinatorDelegate, with code: String) {
        self.networkingService = networkingService
        self.authRequest = networkingService.buildAuthRequest(code)
        self.delegate = delegate
    }
    
    func successAuth(code: String, state: String) {
        networkingService.getAccessToken(code, stateString: state) { success in
            DispatchQueue.main.async {
                if success {
                    self.webAsystNetworking.preloadUserData { status, _, _ in
                        switch status {
                        case .authorizedButProfileIsEmpty,.authorizedButNoneInstallsAndProfileIsEmpty,.authorizedButNoneInstalls:
                            self.delegate?.listOrProfileIsEmpty(status)
                        case .authorized:
                            self.delegate?.successAuth()
                        case .networkError, .error:
                            self.delegate?.errorAuth()
                        case .nonAuthorized:
                            self.delegate?.errorAuth()
                        }
                    }
                    UserDefaults.standard.setValue(false, forKey: "firstLaunch")
                } else {
                    self.delegate?.errorAuth()
                }
            }
        }
        
    }
    
}
