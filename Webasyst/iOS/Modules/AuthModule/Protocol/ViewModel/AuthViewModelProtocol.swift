//
//  File.swift
//  Webasyst
//
//  Created by Леонид Лукашевич on 30.09.2023.
//

import Foundation

protocol AuthViewModelProtocol: AnyObject {
    var authRequest: URLRequest? { get }
    init(networkingService: WebasystNetworking, delegate: AuthCoordinatorDelegate, with code: String)
    func successAuth(code: String, state: String)
}
