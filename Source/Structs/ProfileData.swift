//
//  UserProfile.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 26.05.2021.
//

import Foundation

/// User profile data structure
public struct ProfileData {
    public let name: String
    public let firstname: String
    public let lastname: String
    public let middlename: String
    public let email: String
    public let userpic_original_crop: Data?
    
    public init(name: String, firstname: String, lastname: String, middlename: String, email: String, userpic_original_crop: Data?) {
        self.name = name
        self.firstname = firstname
        self.lastname = lastname
        self.middlename = middlename
        self.email = email
        self.userpic_original_crop = userpic_original_crop
    }
}
