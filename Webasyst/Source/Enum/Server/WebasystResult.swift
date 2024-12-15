//
//  WebasystResult.swift
//  Webasyst
//
//  Created by Леонид Лукашевич on 11.12.2024.
//

public
enum WebasystResult<T: Any> {
    
    case success(_ result: T)
    case failure(_ error: WebasystError)
    
}
