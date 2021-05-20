//
//  WebasystDataModel.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 17.05.2021.
//

import Foundation
import CoreData

public class WebasystDataModel {
    
    class WebasystPersistentContainer: NSPersistentContainer {
        override open class func defaultDirectoryURL() -> URL {
            let urlForApplicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            
            let url = urlForApplicationSupportDirectory.appendingPathComponent(WebasystDBConfig.dbFolder)
            
            if FileManager.default.fileExists(atPath: url.path) == false {
                do {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    print("Can not create storage folder")
                }
            }
            
            return url
        }
    }
    
    private let databaseName = "WebasystAppDataModel"
    
    private lazy var persistentContainer: NSPersistentContainer? = {
        let modelURL = Bundle(for: WebasystDataModel.self)
            .url(forResource: databaseName, withExtension: "momd")
        
        guard let model = modelURL.flatMap(NSManagedObjectModel.init) else {
            print("Webasyst Library model initialization error")
            return nil
        }
        
        var container: WebasystPersistentContainer
        
        container = WebasystPersistentContainer(name: databaseName, managedObjectModel: model)
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                print("Unexpected error: \(error), \(error.userInfo)")
            } else if let error = error {
                print("Unexpected error: \(error)")
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
            print("Failed to get managed objects")
            return nil
        }
    }
}

//MARK: Internal method
extension WebasystDataModel {
    
    internal func saveInstall(_ userInstall: UserInstall, accessToken: String) {
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: installEntityName)
        request.predicate = NSPredicate(format: "clientId == %@", userInstall.clientId)
        
        guard let context = managedObjectContext else { return }
        
        do {
            guard let result = try context.fetch(request) as? [InstallList] else {
                print("InstallList request error")
                return
            }
            if result.isEmpty {
                let install = NSEntityDescription.insertNewObject(forEntityName: installEntityName, into: context) as! InstallList
                install.name = userInstall.name
                install.clientId = userInstall.clientId
                install.domain = userInstall.domain
                install.url = userInstall.url
                install.accessToken = accessToken
                save()
            } else {
                result.first?.name = userInstall.name
                result.first?.clientId = userInstall.clientId
                result.first?.domain = userInstall.domain
                result.first?.url = userInstall.domain
                result.first?.accessToken = userInstall.accessToken
                save()
            }
        } catch { }
        
    }
    
    internal func getInstall(with clientId: String) -> UserInstall? {
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: installEntityName)
        request.predicate = NSPredicate(format: "clientId == %@", clientId)
        
        guard let context = managedObjectContext else { return nil }
        
        do {
            guard let result = try context.fetch(request) as? [InstallList]? else {
                return nil
            }
            if !(result?.isEmpty ?? true) {
                let install = UserInstall(name: result?[0].name ?? "", domain: result?[0].url ?? "", clientId: result?[0].accessToken ?? "", accessToken: result?[0].domain ?? "", url: result?[0].clientId ?? "")
                return install
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }
    
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
                userInstall.append(UserInstall(name: task.name ?? "", domain: task.url ?? "", clientId: task.accessToken ?? "", accessToken: task.domain ?? "", url: task.clientId ?? ""))
            }
            return userInstall
        } catch {
            print("Unexpected error: \(error)")
            return nil
        }
    }
    
    func deleteInstall(clientId: String) {
        guard let context = self.managedObjectContext else { return }
        
        let deleteFetch = NSFetchRequest<NSFetchRequestResult>(entityName: installEntityName)
        deleteFetch.predicate = NSPredicate(format: "clientId == %@", clientId)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: deleteFetch)
        
        do {
            try context.execute(deleteRequest)
            self.save()
        } catch {
            print ("There was an error")
        }
    }
    
    func resetInstallList() {
        guard let context = managedObjectContext else { return }
        let deleteFetch = NSFetchRequest<NSFetchRequestResult>(entityName: installEntityName)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: deleteFetch)
        do {
            try context.execute(deleteRequest)
            self.save()
        } catch {
            print ("There was an error")
        }
    }
    
}

//MARK: Private method
extension WebasystDataModel {
    
    fileprivate func save() {
        guard let managedObjectContext = managedObjectContext else {
            return
        }
        
        if managedObjectContext.hasChanges {
            do {
                try managedObjectContext.save()
            } catch {
                let nserror = error as NSError
                print("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
    
}

//MARK: Profile data
extension WebasystDataModel {
    
    func saveProfileData(_ user: UserData, avatar: Data) {
        
        guard let context = managedObjectContext else { return }
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: profileEntityName)
        request.predicate = NSPredicate(format: "email == %@", user.email[0].value)
        
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
                profile.email = user.email[0].value
                profile.userPic = avatar
                self.save()
            } else {
                result.first?.fullName = user.name
                result.first?.firstName = user.firstname
                result.first?.lastName = user.lastname
                result.first?.middleName = user.middlename
                result.first?.userPic = avatar
                self.save()
            }
        } catch { }
        
    }
    
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
        } catch { }
    }
    
    func deleteProfileData() {
        guard let context = managedObjectContext else { return }
        let deleteFetch = NSFetchRequest<NSFetchRequestResult>(entityName: profileEntityName)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: deleteFetch)
        do {
            try context.execute(deleteRequest)
            self.save()
        } catch {
            print ("There was an error")
        }
    }
    
}
