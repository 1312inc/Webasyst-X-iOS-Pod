//
//  InstallList+CoreDataProperties.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 28.05.2021.
//
//

import Foundation
import CoreData


extension InstallList {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<InstallList> {
        return NSFetchRequest<InstallList>(entityName: "InstallList")
    }

    @NSManaged public var accessToken: String?
    @NSManaged public var clientId: String?
    @NSManaged public var domain: String?
    @NSManaged public var image: Data?
    @NSManaged public var name: String?
    @NSManaged public var url: String?

}

extension InstallList : Identifiable {

}
