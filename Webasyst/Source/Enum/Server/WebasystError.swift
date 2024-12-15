//
//  WebasystError.swift
//  Webasyst
//
//  Created by Леонид Лукашевич on 15.12.2024.
//

public
struct WebasystError: Error, Equatable {
    
    public let localizedError: String
    public let statusCode: Int?
    public let errorValue: String?
    
    public init(localizedError: String, statusCode: Int? = nil, errorValue: String? = nil) {
        self.localizedError = localizedError
        self.statusCode = statusCode
        self.errorValue = errorValue
    }
    
    public var localizedDescription: String {
        localizedError
    }
    
    static func getError(_ model: ErrorTypeModel) -> WebasystError {
        let error = model.error
        let type = model.type
        let methodName = model.methodName
        
        switch type {
        case .unowned(let response):
            let dataStr = String(data: response.data, encoding: .utf8) ?? ""
            
            let errorDescription = WebasystApp.getDefaultLocalizedString(withKey: "error.unknown", comment: "Error description")
                .replacingOccurrences(of: "@MTD", with: methodName)
                .replacingOccurrences(of: "@CD", with: response.statusCode.description)
                .replacingOccurrences(of: "@DT", with: dataStr)
            
            let error = WebasystError(localizedError: errorDescription, statusCode: error.statusCode, errorValue: error.errorValue)
            
            return error
        case .decodingData:
            let loc = WebasystApp.getDefaultLocalizedString(withKey: "unableToDecodeResponsedData", comment: "Unable to decode server response")
            
            let errorDescription = WebasystApp.getDefaultLocalizedString(withKey: "error.default", comment: "Error description")
                .replacingOccurrences(of: "@INSTL", with: "")
                .replacingOccurrences(of: "@MTD", with: methodName)
                .replacingOccurrences(of: "@LER", with: loc)
                .replacingOccurrences(of: "@ER", with: error.localizedError)
            
            let error = WebasystError(localizedError: errorDescription, statusCode: error.statusCode, errorValue: error.errorValue)
            
            return error
        case .decodingParameters(let domain):
            let installDescription: String
            
            if let domain, !domain.isEmpty {
                installDescription = WebasystApp.getDefaultLocalizedString(withKey: "error.default.install", comment: "Install name")
                    .replacingOccurrences(of: "@INSTL", with: domain)
            } else {
                installDescription = ""
            }
            
            let loc = WebasystApp.getDefaultLocalizedString(withKey: "unableToGetDecodedParameters", comment: "Unable to get decoded parameters")
            
            let errorDescription = WebasystApp.getDefaultLocalizedString(withKey: "error.default", comment: "Error description")
                .replacingOccurrences(of: "@INSTL", with: installDescription)
                .replacingOccurrences(of: "@MTD", with: methodName)
                .replacingOccurrences(of: "@LER", with: loc)
                .replacingOccurrences(of: "@ER", with: error.localizedError)
            
            let error = WebasystError(localizedError: errorDescription, statusCode: error.statusCode, errorValue: error.errorValue)
            
            return error
        case .standart(let domain):
            let installDescription: String
            
            if let domain, !domain.isEmpty {
                installDescription = WebasystApp.getDefaultLocalizedString(withKey: "error.default.install", comment: "Install name")
                    .replacingOccurrences(of: "@INSTL", with: domain)
            } else {
                installDescription = ""
            }
            
            let errorDescription = WebasystApp.getDefaultLocalizedString(withKey: "error.default", comment: "Error description")
                .replacingOccurrences(of: "@INSTL", with: installDescription)
                .replacingOccurrences(of: "@MTD", with: methodName)
                .replacingOccurrences(of: "@LER", with: error.localizedError)
                .replacingOccurrences(of: "@ER", with: "")
            
            let error = WebasystError(localizedError: errorDescription, statusCode: error.statusCode, errorValue: error.errorValue)
            
            return error
        }
    }
}
