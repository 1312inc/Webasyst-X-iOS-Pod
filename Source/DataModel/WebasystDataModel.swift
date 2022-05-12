//
//  WebasystDataModel.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 17.05.2021.
//

import Foundation
import CoreData

public class WebasystDataModel {
    
    /// Obtaining a library database
    class WebasystPersistentContainer: NSPersistentContainer {
        override open class func defaultDirectoryURL() -> URL {
            let urlForApplicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            
            let url = urlForApplicationSupportDirectory.appendingPathComponent(WebasystDBConfig.dbFolder)
            
            if FileManager.default.fileExists(atPath: url.path) == false {
                do {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                } catch let error {
                    print(NSError(domain: "Webasyst error: \(error.localizedDescription)", code: -1, userInfo: nil))
                }
            }
            
            return url
        }
    }
    
    private lazy var persistentContainer: NSPersistentContainer? = {
        let modelURL = Bundle(for: WebasystDataModel.self)
            .url(forResource: WebasystDBConfig.databaseName, withExtension: "momd")
        
        guard let model = modelURL.flatMap(NSManagedObjectModel.init) else {
            print(NSError(domain: "Webasyst error: Library model initialization error", code: 500, userInfo: nil))
            return nil
        }
        
        var container: WebasystPersistentContainer
        
        container = WebasystPersistentContainer(name: WebasystDBConfig.databaseName, managedObjectModel: model)
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                print(NSError(domain: "Webasyst error: \(error), \(error.userInfo)", code: 500, userInfo: nil))
            } else if let error = error {
                print(NSError(domain: "Webasyst error: \(error)", code: 500, userInfo: nil))
            }
        })
        
        return container
    }()
    
    private lazy var installEntityName: String = {
        return String(describing: InstallList.self)
    } ()
    
    private lazy var profileEntityName: String = {
        return String(describing: Profile.self)
    } ()
    
    private var managedObjectContext: NSManagedObjectContext?
    
    public init?() {
        managedObjectContext = persistentContainer?.viewContext
        
        guard managedObjectContext != nil else {
            print(NSError(domain: "Webasyst error: Failed to get managed objects", code: 500, userInfo: nil))
            return nil
        }
    }
}

//MARK: Internal method
extension WebasystDataModel {
    
    /// Saving a user installation
    /// - Parameters:
    ///   - userInstall: Installation information in UserInstall format (Warning! If the installation already exists in the database its data will be updated)
    internal func saveInstall(_ userInstall: UserInstall) {
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: installEntityName)
        request.predicate = NSPredicate(format: "clientId == %@", userInstall.id)
        
        guard let context = managedObjectContext else { return }
        
        do {
            guard let result = try context.fetch(request) as? [InstallList] else {
                print(NSError(domain: "Webasyst error: InstallList request error", code: 501, userInfo: nil))
                return
            }
            if result.isEmpty {
                let install = NSEntityDescription.insertNewObject(forEntityName: installEntityName, into: context) as! InstallList
                install.name = userInstall.name
                install.clientId = userInstall.id
                install.domain = userInstall.domain
                install.url = userInstall.url
                install.accessToken = userInstall.accessToken
                install.image = userInstall.image
                install.imageLogo = userInstall.imageLogo ?? false
                install.logoText = userInstall.logoText
                install.logoColorText = userInstall.logoTextColor
                install.cloudPlanId = userInstall.cloudPlanId
                install.cloudExpireDate = userInstall.cloudExpireDate
                install.cloudTrial = userInstall.cloudTrial ?? false
                save()
            } else {
                result.first?.name = userInstall.name
                result.first?.clientId = userInstall.id
                result.first?.domain = userInstall.domain
                result.first?.url = userInstall.url
                result.first?.accessToken = userInstall.accessToken
                result.first?.image = userInstall.image
                result.first?.imageLogo = userInstall.imageLogo ?? false
                result.first?.logoText = userInstall.logoText
                result.first?.logoColorText = userInstall.logoTextColor
                result.first?.cloudPlanId = userInstall.cloudPlanId
                result.first?.cloudExpireDate = userInstall.cloudExpireDate
                result.first?.cloudTrial = userInstall.cloudTrial ?? false
                save()
            }
        } catch { }
        
    }
    
    /// Obtaining user installation information
    /// - Parameter clientId: install clientId
    /// - Returns: Returns the installation in UserInstall format
    internal func getInstall(with clientId: String) -> UserInstall? {
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: installEntityName)
        request.predicate = NSPredicate(format: "clientId == %@", clientId)
        
        guard let context = managedObjectContext else { return nil }
        
        do {
            guard let result = try context.fetch(request) as? [InstallList] else {
                return nil
            }
            if !(result.isEmpty) {
                let install = UserInstall(name: result.first?.name ?? "", domain: result.first?.domain ?? "", id: result.first?.clientId ?? "", accessToken: result.first?.accessToken ?? "", url: result.first?.url ?? "", image: result.first?.image, imageLogo: result.first?.imageLogo, logoText: result.first?.logoText ?? "", logoTextColor: result.first?.logoColorText ?? "", cloudPlanId: result.first?.cloudPlanId, cloudExpireDate: result.first?.cloudExpireDate, cloudTrial: result.first?.cloudTrial)
                return install
            } else {
                return nil
            }
        } catch let error {
            print(NSError(domain: "Webasyst database error (method: getInstall): \(error.localizedDescription)", code: 501, userInfo: nil))
            return nil
        }
    }
    
    /// Getting a list of all user install
    /// - Returns: Returns the list of user installations in UserInstall format
    internal func getInstallList() -> [UserInstall]? {
        guard let context = managedObjectContext else {
            return nil
        }
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: installEntityName)
        
        do {
            guard let tasks = try context.fetch(fetchRequest) as? [InstallList] else {
                return nil
            }
            
            var userInstall: [UserInstall] = []
            for task in tasks {
                userInstall.append(UserInstall(name: task.name ?? "", domain: task.domain ?? "", id: task.clientId ?? "", accessToken: task.accessToken ?? "", url: task.url ?? "", image: task.image, imageLogo: task.imageLogo, logoText: task.logoText ?? "", logoTextColor: task.logoColorText ?? "", cloudPlanId: task.cloudPlanId, cloudExpireDate: task.cloudExpireDate, cloudTrial: task.cloudTrial))
            }
            return userInstall
        } catch let error {
            print(NSError(domain: "Webasyst database error (method: getInstallList): \(error.localizedDescription)", code: 501, userInfo: nil))
            return nil
        }
    }
    
    /// Deleting a user installation
    /// - Parameter clientId: clientId setting
    func deleteInstall(clientId: String) {
        guard let context = self.managedObjectContext else { return }
        
        let deleteFetch = NSFetchRequest<NSFetchRequestResult>(entityName: installEntityName)
        deleteFetch.predicate = NSPredicate(format: "clientId == %@", clientId)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: deleteFetch)
        
        do {
            try context.execute(deleteRequest)
            self.save()
        } catch let error {
            print(NSError(domain: "Webasyst database error (method: deleteInstall): \(error.localizedDescription)", code: 501, userInfo: nil))
        }
    }
    
    /// Deleting all user install list
    func resetInstallList() {
        
        guard let context = managedObjectContext else { return }
        let deleteFetch = NSFetchRequest<NSFetchRequestResult>(entityName: installEntityName)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: deleteFetch)
        
        do {
            try context.execute(deleteRequest)
            self.save()
        } catch let error {
            print(NSError(domain: "Webasyst database error(method: resetInstallList): \(error.localizedDescription)", code: 501, userInfo: nil))
        }
    }
    
}

//MARK: Private method
extension WebasystDataModel {
    
    /// Saving the database context
    fileprivate func save() {
        guard let managedObjectContext = managedObjectContext else {
            return
        }
        
        if managedObjectContext.hasChanges {
            do {
                try managedObjectContext.save()
            } catch {
                let nserror = error as NSError
                print(NSError(domain: "Webasyst Database error(method: save): Unresolved error \(nserror), \(nserror.userInfo)", code: 500, userInfo: nil))
            }
        }
    }
    
}

//MARK: Profile data
extension WebasystDataModel {
    
    func creator(_installs: [UserInstall], url: URL) {
         var dictionary = Dictionary<String?, SettingsListModel>()
         _installs.forEach {
             dictionary[$0.name] = SettingsListModel(countSelected: 0, isLast: false, id: $0.id)
         }
         let encodedData = try? NSKeyedArchiver.archivedData(withRootObject: dictionary, requiringSecureCoding: false)
         try? encodedData?.write(to: url)
    }
    
    /// Saving installs data
    func createNew() {
        let url = WebasystApp.url()
        guard let installs = getInstallList() else { return }
        guard let object = try? Data(contentsOf: url) else { return creator(_installs: installs, url: url) }
           if let archivedInstalls = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(object) as? Dictionary<String,SettingsListModel>, archivedInstalls?.count != installs.count {
            creator(_installs: installs, url: url)
        }
    }
    
    /// Saving profile data
    /// - Parameters:
    ///   - user: User data
    ///   - avatar: user avatar image
    func saveProfileData(_ user: UserData, avatar: Data) {
        
        guard let context = managedObjectContext else { return }
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: profileEntityName)
        request.predicate = NSPredicate(format: "email == %@", user.email.first?.value ?? "")
        
        do {
            guard let result = try context.fetch(request) as? [Profile] else {
                return
            }
            if result.isEmpty {
                let profile = NSEntityDescription.insertNewObject(forEntityName: self.profileEntityName, into: context) as! Profile
                profile.fullName = user.name
                profile.firstName = user.firstname
                profile.lastName = user.lastname
                profile.middleName = user.middlename
                profile.email = user.email.first?.value ?? ""
                profile.userPic = avatar
                self.save()
            } else {
                result.first?.fullName = user.name
                result.first?.firstName = user.firstname
                result.first?.lastName = user.lastname
                result.first?.middleName = user.middlename
                result.first?.userPic = avatar
                result.first?.email = user.email.first?.value ?? ""
                self.save()
            }
        } catch let error {
            print(NSError(domain: "Webasyst Database error(method: saveProfileData): \(error.localizedDescription)", code: 502, userInfo: nil))
        }
        
    }
    
    func saveNewAvatar(_ image: Data) {
        guard let context = managedObjectContext else { return }
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: profileEntityName)
        
        do {
            guard let result = try context.fetch(request) as? [Profile] else { return }
            result.first?.userPic = image
            self.save()
        } catch let error {
            print(NSError(domain: "Webasyst Database error(method: saveProfileData): \(error.localizedDescription)", code: 502, userInfo: nil))
        }
        
    }
    
    /// Retrieving user data from the database
    /// - Returns: User data in ProfileData format
    func getProfile(completion: @escaping (ProfileData?) -> ()) {
        
        guard let context = managedObjectContext else { return }
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: profileEntityName)
        
        do {
            guard let result = try context.fetch(request) as? [Profile] else {
                completion(nil)
                return
            }
            if !result.isEmpty {
                let profileData = ProfileData(name: result.first?.fullName ?? "", firstname: result.first?.firstName ?? "", lastname: result.first?.lastName ?? "", middlename: result.first?.middleName ?? "", email: result.first?.email ?? "", userpic_original_crop: result.first?.userPic)
                completion(profileData)
            } else {
                completion(nil)
            }
        } catch let error {
            print(NSError(domain: "Webasyst Database error(method: getProfile): \(error.localizedDescription)", code: 502, userInfo: nil))
        }
    }
    
    /// Deleting user data
    func deleteProfileData() {
        guard let context = managedObjectContext else { return }
        let deleteFetch = NSFetchRequest<NSFetchRequestResult>(entityName: profileEntityName)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: deleteFetch)
        do {
            try context.execute(deleteRequest)
            self.save()
        } catch let error {
            print(NSError(domain: "Webasyst Database error(method: deleteProfileData): \(error.localizedDescription)", code: 502, userInfo: nil))
        }
    }
    
}
