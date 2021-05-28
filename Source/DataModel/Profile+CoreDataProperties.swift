//
//  Profile+CoreDataProperties.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 28.05.2021.
//
//

import Foundation
import CoreData


extension Profile {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Profile> {
        return NSFetchRequest<Profile>(entityName: "Profile")
    }

    @NSManaged public var email: String?
    @NSManaged public var firstName: String?
    @NSManaged public var fullName: String?
    @NSManaged public var lastName: String?
    @NSManaged public var middleName: String?
    @NSManaged public var userPic: Data?

}

extension Profile : Identifiable {

}
