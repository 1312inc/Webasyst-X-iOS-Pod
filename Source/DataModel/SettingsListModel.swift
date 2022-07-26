//
//  SettingsListModel.swift
//  Webasyst
//
//  Created by Andrey Gubin on 12.05.2022.
//

import Foundation

public class SettingsListModel: NSObject, NSCoding {
    
    enum Key: String {
        case selected = "selected"
        case isLast = "isLast"
        case name = "name"
    }
    
    public func encode(with coder: NSCoder) {
        coder.encode(countSelected, forKey: Key.selected.rawValue)
        coder.encode(isLast, forKey: Key.isLast.rawValue)
        coder.encode(name, forKey: Key.name.rawValue)
    }
    
    public init(countSelected: Int, isLast: Bool, name: String) {
        self.countSelected = countSelected
        self.isLast = isLast
        self.name = name
    }
    
    required convenience public init(coder: NSCoder) {
        self.init(countSelected: 0, isLast: false, name: "")
        countSelected = coder.decodeInteger(forKey: Key.selected.rawValue)
        isLast = coder.decodeBool(forKey: Key.isLast.rawValue)
        name = coder.decodeObject(forKey: Key.name.rawValue) as! String
    }
    
    public var countSelected = 0
    public var isLast = false
    public var name = ""
}
