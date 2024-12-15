//
//  AuthCoordinatorDelegate.swift
//  Webasyst
//
//  Created by Леонид Лукашевич on 30.09.2023.
//

import Foundation

protocol AuthCoordinatorDelegate: AnyObject {
    func successAuth(_ status: UserStatus)
    func errorAuth(_ error: WebasystError)
}
