//
//  AuthViewModel.swift
//  WebXApp
//
//  Created by Виктор Кобыхно on 1/13/21.
//

import Foundation

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
                    self.webAsystNetworking.preloadUserData { result in
                        switch result {
                        case .success(let status):
                            self.delegate?.successAuth(status)
                            UserDefaults.standard.setValue(false, forKey: "firstLaunch")
                        case .failure(let error):
                            self.delegate?.errorAuth(error)
                        }
                    }
                } else {
                    self.delegate?.errorAuth("Unable to get access token")
                }
            }
        }
    }
}
