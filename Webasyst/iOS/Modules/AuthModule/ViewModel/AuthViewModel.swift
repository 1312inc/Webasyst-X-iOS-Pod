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
    private var webasystNetworking = WebasystUserNetworking()
    
    var authRequest: URLRequest?
    
    init(networkingService: WebasystNetworking, delegate: AuthCoordinatorDelegate, with code: String) {
        self.networkingService = networkingService
        self.authRequest = networkingService.buildAuthRequest(code)
        self.delegate = delegate
    }
    
    func successAuth(code: String, state: String) {
        networkingService.getAccessToken(code, stateString: state) { success in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                
                if success {
                    webasystNetworking.preloadUserData { [weak self] result in
                        guard let self else { return }
                        
                        switch result {
                        case .success(let status):
                            delegate?.successAuth(status)
                            UserDefaults.standard.setValue(false, forKey: "firstLaunch")
                        case .failure(let error):
                            let errorType = ErrorTypeModel(error: error, type: .standart(), methodName: "successAuth")
                            let error = WebasystError.getError(errorType)
                            
                            delegate?.errorAuth(error)
                        }
                    }
                } else {
                    let loc = WebasystApp.getDefaultLocalizedString(withKey: "error.token")
                    
                    let webasystError = WebasystError(localizadError: loc)
                    
                    let errorType = ErrorTypeModel(error: webasystError, type: .standart(), methodName: "successAuth")
                    let error = WebasystError.getError(errorType)
                    
                    delegate?.errorAuth(error)
                }
            }
        }
    }
}
