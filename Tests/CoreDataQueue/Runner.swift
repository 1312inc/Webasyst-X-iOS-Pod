import UIKit
@testable import Webasyst

final class QueueChecks {
    private let lock = NSLock()
    private var assertions = 0
    private var failures = [String]()

    func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        let passed = condition()
        lock.lock()
        assertions += 1
        if !passed { failures.append(name) }
        lock.unlock()
    }

    func finish() {
        lock.lock()
        let value = failures.isEmpty
            ? "PASS: \(assertions) assertions"
            : "FAIL: \(failures.joined(separator: ", "))"
        lock.unlock()
        Self.write(value)
    }

    static func write(_ value: String) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("verdict.txt")
        try! value.write(to: url, atomically: true, encoding: .utf8)
        FileHandle.standardOutput.write(Data((value + "\n").utf8))
    }
}

@main
final class QueueTestApp: UIResponder, UIApplicationDelegate {
    private let checks = QueueChecks()
    private var retainedModel: WebasystDataModel?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FileHandle.standardOutput.write(Data(("QUEUE_TEST_PID \(ProcessInfo.processInfo.processIdentifier)\n").utf8))
        WebasystDBConfig.dbFolder = "WebasystCoreDataQueueRegression"
        let scenario = ProcessInfo.processInfo.arguments.last ?? "regression"
        QueueChecks.write("RUNNING " + scenario)
        guard let model = WebasystDataModel() else {
            QueueChecks.write("FAIL: model initialization")
            return true
        }
        retainedModel = model

        if scenario == "seed" {
            model.resetInstallList()
            model.deleteProfileData()
            model.saveInstall(install("legacy", name: "Legacy install"))
            model.saveProfileData(profile("Legacy"), avatar: Data([1, 2, 3]))
            checks.check(model.getInstall(with: "legacy")?.name == "Legacy install", "legacy install saved")
            checks.check(model.getProfile()?.name == "Legacy", "legacy profile saved")
            checks.finish()
        } else if scenario == "background" {
            DispatchQueue.global().async {
                _ = model.getInstallList()
                QueueChecks.write("PASS: background read completed")
            }
        } else {
            checks.check(Thread.isMainThread, "main control")
            checks.check(model.getInstall(with: "legacy")?.name == "Legacy install", "existing SQLite install preserved")
            checks.check(model.getProfile()?.name == "Legacy", "existing SQLite profile preserved")
            checks.check(model.getProfile()?.firstname == "First", "existing first name preserved")
            checks.check(model.getProfile()?.lastname == "Last", "existing last name preserved")
            checks.check(model.getProfile()?.middlename == "Middle", "existing middle name preserved")
            checks.check(model.getProfile()?.phone == "+10000000000", "existing phone preserved")
            checks.check(model.getProfile()?.userpic_original_crop == Data([1, 2, 3]), "existing avatar preserved")
            DispatchQueue.global().async { [self] in
                runRegression(model)
            }
        }
        return true
    }

    private func install(_ id: String, name: String = "Fixture") -> UserInstall {
        UserInstall(name: name, domain: "fixture.invalid", id: id, accessToken: "fixture-token",
                    url: "https://fixture.invalid", image: Data([4, 5]), imageLogo: true,
                    logoText: "Q", logoTextColor: "#123456", cloudPlanId: "fixture-plan",
                    cloudExpireDate: "2030-01-01", cloudTrial: true)
    }

    private func profile(_ name: String) -> UserData {
        UserData(name: name, firstname: "First", lastname: "Last", middlename: "Middle",
                 email: [Connectivity(value: "fixture@example.invalid")],
                 phone: [Connectivity(value: "+10000000000")], userpic_original_crop: "")
    }

    private func runRegression(_ model: WebasystDataModel) {
        checks.check(!Thread.isMainThread, "background control")
        checks.check(model.getInstallList()?.contains(where: { $0.id == "legacy" }) == true, "background list")
        checks.check(model.getInstall(with: "missing") == nil, "missing install")
        let original = install("crud")
        model.saveInstall(original)
        checks.check(model.getInstall(with: "crud") == original, "install fields round trip")
        model.saveInstall(install("crud", name: "Updated"))
        checks.check(model.getInstall(with: "crud")?.name == "Updated", "install update")
        checks.check(model.getInstallList()?.filter { $0.id == "crud" }.count == 1, "update does not duplicate")
        model.deleteInstall(clientId: "crud")
        checks.check(model.getInstall(with: "crud") == nil, "install delete")
        checks.check(model.getInstall(with: "legacy") != nil, "delete preserves other install")
        model.saveInstall(original)
        checks.check(model.getInstall(with: "crud") == original, "install recreation after batch delete")
        model.deleteInstall(clientId: "crud")

        model.saveProfileData(profile("Updated profile"), avatar: Data([6, 7]))
        checks.check(model.getProfile()?.name == "Updated profile", "background profile update")
        checks.check(model.getProfile()?.email == "fixture@example.invalid", "profile fields round trip")
        model.saveNewAvatar(Data([8, 9]))
        checks.check(model.getProfile()?.userpic_original_crop == Data([8, 9]), "avatar update")
        model.deleteProfileData()
        checks.check(model.getProfile() == nil, "profile delete")
        model.saveProfileData(profile("Recreated profile"), avatar: Data([10]))
        checks.check(model.getProfile()?.name == "Recreated profile", "profile recreation after batch delete")
        model.deleteProfileData()

        let api = WebasystApp()
        checks.check(api.getAllUserInstall()?.contains(where: { $0.id == "legacy" }) == true, "public background list")
        checks.check(api.getUserInstall("legacy")?.id == "legacy", "public background lookup")
        checks.check(api.getProfileData() == nil, "public background empty profile")

        let separateModels = (0..<8).compactMap { _ in WebasystDataModel() }
        checks.check(separateModels.count == 8, "separate SDK instances initialized")
        let sharedID = "shared-install"
        let separateGroup = DispatchGroup()
        for (index, separate) in separateModels.enumerated() {
            separateGroup.enter()
            DispatchQueue.global().async { [self] in
                separate.saveInstall(install(sharedID, name: "Writer \(index)"))
                separate.saveProfileData(profile("Writer \(index)"), avatar: Data([11]))
                checks.check(separate.getInstall(with: sharedID)?.id == sharedID, "separate instance lookup \(index)")
                separateGroup.leave()
            }
        }
        separateGroup.wait()
        checks.check(model.getInstallList()?.filter { $0.id == sharedID }.count == 1, "separate instances do not duplicate installs")
        model.deleteInstall(clientId: sharedID)
        checks.check(model.getInstall(with: sharedID) == nil, "separate instance insert can be deleted")
        checks.check(model.getProfile()?.name.hasPrefix("Writer ") == true, "separate instance profile saved")
        model.deleteProfileData()

        let group = DispatchGroup()
        for worker in 0..<6 {
            group.enter()
            DispatchQueue.global().async { [self] in
                for index in 0..<12 {
                    let id = "worker-\(worker)-\(index)"
                    model.saveInstall(install(id))
                    checks.check(model.getInstall(with: id)?.id == id, "concurrent lookup \(id)")
                    checks.check(model.getInstallList() != nil, "concurrent list \(id)")
                    if index % 4 == 0 {
                        group.enter()
                        DispatchQueue.main.async { [self] in
                            checks.check(model.getInstallList() != nil, "main read during background writes \(id)")
                            group.leave()
                        }
                    }
                }
                group.leave()
            }
        }
        for worker in 0..<4 {
            group.enter()
            DispatchQueue.global().async { [self] in
                for index in 0..<6 {
                    autoreleasepool {
                        // The last reference is released on this worker, exercising reset/deinit too.
                        let temporary = WebasystDataModel()
                        checks.check(temporary?.getInstall(with: "legacy")?.id == "legacy", "background init/read/deinit \(worker)-\(index)")
                    }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [self] in
            checks.check(model.getInstallList()?.count == 73, "all concurrent writes persisted")
            checks.check(model.getInstall(with: "legacy")?.name == "Legacy install", "main read after background writes")
            DispatchQueue.global().async { [self] in
                model.resetInstallList()
                checks.check(model.getInstallList()?.isEmpty == true, "reset list")
                checks.finish()
            }
        }
    }
}

final class QueueTestScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        window.rootViewController = controller
        self.window = window
        window.makeKeyAndVisible()
    }
}
