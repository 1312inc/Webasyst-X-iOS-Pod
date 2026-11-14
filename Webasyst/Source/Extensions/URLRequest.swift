//
//  URLRequest.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 14.05.2021.
//

import Foundation

extension URLRequest {
    mutating func setURLEncodedFormData(_ parameters: Parameters) throws {
        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._")
        func encode(_ value: String) throws -> String {
            guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
                throw FormURLEncodingError.invalidString
            }
            return encoded.replacingOccurrences(of: "%20", with: "+")
        }

        let fields = try parameters.sorted { $0.key < $1.key }.map { key, value in
            try "\(encode(key))=\(encode(value))"
        }
        httpBody = Data(fields.joined(separator: "&").utf8)
        setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    }
    
    /// Encoding query parameters into Form Data format
    /// - Parameters:
    ///   - parameters: Request parameters
    ///   - encoding: Encoding format
    /// - Throws: Encoding error in request parameters
    mutating func setMultipartFormData(_ parameters: Parameters, encoding: String.Encoding) throws {

        let makeRandom = { UInt32.random(in: (.min)...(.max)) }
        let boundary = String(format: "------------------------%08X%08X", makeRandom(), makeRandom())

        let contentType: String = try {
            guard let charset = CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)) else {
                throw MultipartFormDataEncodingError.characterSetName
            }
            return "multipart/form-data; charset=\(charset); boundary=\(boundary)"
        }()
        setValue(contentType, forHTTPHeaderField: "Content-Type")

        httpBody = try {
            var body = Data()

            for (rawName, rawValue) in parameters {
                if !body.isEmpty {
                    body.append("\r\n".data(using: .utf8)!)
                }

                body.append("--\(boundary)\r\n".data(using: .utf8)!)

                guard
                    rawName.canBeConverted(to: encoding),
                    let disposition = "Content-Disposition: form-data; name=\"\(rawName)\"\r\n".data(using: encoding) else {
                    throw MultipartFormDataEncodingError.name(rawName)
                }
                body.append(disposition)

                body.append("\r\n".data(using: .utf8)!)

                guard let value = rawValue.data(using: encoding) else {
                    throw MultipartFormDataEncodingError.value(rawValue, name: rawName)
                }

                body.append(value)
            }

            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

            return body
        }()
    }
}

enum MultipartFormDataEncodingError: Error {
    case characterSetName
    case name(String)
    case value(String, name: String)
}

private enum FormURLEncodingError: Error {
    case invalidString
}
