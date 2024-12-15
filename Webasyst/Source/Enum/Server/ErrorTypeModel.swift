//
//  ErrorTypeModel.swift
//  Webasyst
//
//  Created by Леонид Лукашевич on 15.12.2024.
//

struct ErrorTypeModel {
    let error: WebasystError
    let type: ServerErrorDescriptionType
    let methodName: String
    
    init(error: WebasystError, type: ServerErrorDescriptionType, methodName: String) {
        self.error = error
        self.type = type
        self.methodName = methodName
    }
    
    init(type: ServerErrorDescriptionType, methodName: String) {
        self.error = WebasystError(localizadError: "")
        self.type = type
        self.methodName = methodName
    }
}
