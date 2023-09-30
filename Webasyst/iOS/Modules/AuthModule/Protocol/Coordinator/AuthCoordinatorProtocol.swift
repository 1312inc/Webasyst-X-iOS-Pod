//
//  AuthCoordinatorDelegate.swift
//  Webasyst
//
//  Created by Леонид Лукашевич on 30.09.2023.
//

import UIKit

protocol AuthCoordinatorProtocol {
    init(_ navigationController: UINavigationController, action: @escaping (WebasystServerAnswer) -> ())
}
