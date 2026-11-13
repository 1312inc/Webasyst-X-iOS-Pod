import XCTest
import Security
@testable import Webasyst

final class WebasystAuthRegressionTests: AuthTestCase {
    func testCatalogKeepsDeniedStoreAndPublishesSlowStoreWithoutWaitingForMetadata() throws {
        seed()
        let app = WebasystApp()
        let catalog = Data(#"""
            [{"id":"denied","domain":"denied.example.invalid","url":"https://denied.example.invalid","name":"Denied"},
             {"id":"ready","domain":"ready.example.invalid","url":"https://ready.example.invalid"},
             {"id":"slow","domain":"slow.example.invalid","url":"https://slow.example.invalid"}]
            """#.utf8)
        let codes = Data(#"{"denied":"code1","ready":"code2","slow":"code3"}"#.utf8)
        let token = Data(#"{"access_token":"fixture-install-token"}"#.utf8)
        let batch = expectation(description: "first available installation")
        let slowRequest = expectation(description: "slow exchange held")
        let slowAvailable = expectation(description: "late token published")
        let metadata = expectation(description: "both metadata requests failed independently")
        metadata.expectedFulfillmentCount = 2
        var slow: AuthURLProtocol?
        var observedSlow = false
        var completionCount = 0
        observe(.webasystInstallationsDidChange) { _ in
            if !observedSlow, app.getUserInstall("slow") != nil {
                observedSlow = true
                slowAvailable.fulfill()
            }
        }
        AuthURLProtocol.handler = { stub in
            switch (stub.request.url?.host, self.normalizedPath(stub)) {
            case ("auth.example.invalid", "id/api/v1/installations"):
                stub.reply(body: catalog)
            case ("auth.example.invalid", "id/api/v1/auth/client"):
                XCTAssertEqual(app.getInstallationCatalog()?.map { $0.metadata.id }, ["denied", "ready", "slow"])
                XCTAssertNil(UserDefaults.standard.string(forKey: "selectDomainUser"))
                stub.reply(body: codes)
            case ("denied.example.invalid", "api.php/token-headless"):
                stub.reply(status: 403, body: Data("<html>Forbidden</html>".utf8))
            case ("ready.example.invalid", "api.php/token-headless"):
                stub.reply(body: token)
            case ("slow.example.invalid", "api.php/token-headless"):
                slow = stub
                slowRequest.fulfill()
            case (_, "api.php/webasyst.getInfo"):
                // Logo and name are optional. A slow or failing response must not block access.
                stub.reply(status: 503)
                metadata.fulfill()
            default:
                XCTFail("Unexpected fixture request")
                stub.fail(URLError(.unsupportedURL))
            }
        }
        app.updateUserInstalls { result in
            completionCount += 1
            XCTAssertEqual(result?.map(\.id), ["denied", "ready", "slow"])
            XCTAssertEqual(app.getAllUserInstall()?.map(\.id), ["ready"])
            XCTAssertEqual(UserDefaults.standard.string(forKey: "selectDomainUser"), "ready")
            batch.fulfill()
        }
        wait(for: [batch, slowRequest], timeout: 5)
        XCTAssertEqual(app.getInstallationCatalog()?.last?.isCheckingAccess, true)
        try XCTUnwrap(slow).reply(body: token)
        wait(for: [slowAvailable, metadata], timeout: 5)
        XCTAssertEqual(app.getAllUserInstall()?.map(\.id).sorted(), ["ready", "slow"])
        XCTAssertEqual(app.getInstallationCatalog()?.first?.metadata.name, "Denied")
        XCTAssertNil(app.getUserInstall("denied"))
        XCTAssertEqual(completionCount, 1)
    }

    func testRetryTargetsOneStoreJoinsExchangeAndKeepsActiveStore() throws {
        seed()
        let app = WebasystApp()
        let currentURL = "https://current.example.invalid"
        XCTAssertTrue(app.profileInstallService?.saveInstall(UserInstall(name: "Current", domain: "current.example.invalid",
            id: "current", accessToken: "cached-token", url: currentURL, logoText: "", logoTextColor: "")) == true)
        UserDefaults.standard.set("current", forKey: "selectDomainUser")
        let catalog = Data(#"""
            [{"id":"current","domain":"current.example.invalid","url":"https://current.example.invalid"},
             {"id":"target","domain":"target.example.invalid","url":"https://target.example.invalid"}]
            """#.utf8)
        let loaded = expectation(description: "catalog")
        AuthURLProtocol.handler = { $0.reply(body: catalog) }
        app.userNetworking.getInstallList { result in
            guard case .success = result else { return XCTFail("Catalog must load") }
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 5)

        let tokenRequest = expectation(description: "one token exchange")
        let failed = expectation(description: "both callers see the rejection")
        failed.expectedFulfillmentCount = 2
        var exchange: AuthURLProtocol?
        var codeRequests = 0
        AuthURLProtocol.handler = { stub in
            switch (stub.request.url?.host, self.normalizedPath(stub)) {
            case ("auth.example.invalid", "id/api/v1/auth/client"):
                codeRequests += 1
                XCTAssertTrue(stub.request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
                stub.reply(body: Data(#"{"target":"fresh-code"}"#.utf8))
            case ("target.example.invalid", "api.php/token-headless"):
                exchange = stub
                tokenRequest.fulfill()
            case ("target.example.invalid", "api.php/webasyst.getInfo"):
                stub.reply(body: Data(#"{"name":"Recovered"}"#.utf8))
            default:
                XCTFail("Retry must not refresh other installations")
                stub.fail(URLError(.unsupportedURL))
            }
        }
        let failure: (WebasystResult<UserInstall>) -> Void = { result in
            guard case .failure(let error) = result else { return XCTFail("Expected failure") }
            XCTAssertEqual(error.statusCode, 403)
            XCTAssertEqual(UserDefaults.standard.string(forKey: "selectDomainUser"), "current")
            failed.fulfill()
        }
        app.retryInstallationAccess(id: "target", completion: failure)
        WebasystApp().retryInstallationAccess(id: "target", completion: failure)
        wait(for: [tokenRequest], timeout: 5)
        try XCTUnwrap(exchange).reply(status: 403, body: Data("<html>Forbidden</html>".utf8))
        wait(for: [failed], timeout: 5)
        XCTAssertEqual(codeRequests, 1)
        XCTAssertNil(app.getUserInstall("target"))

        let recovered = expectation(description: "next retry succeeded")
        let metadata = expectation(description: "metadata request sent")
        AuthURLProtocol.handler = { stub in
            switch self.normalizedPath(stub) {
            case "id/api/v1/auth/client":
                codeRequests += 1
                stub.reply(body: Data(#"{"target":"second-code"}"#.utf8))
            case "api.php/token-headless":
                stub.reply(body: Data(#"{"access_token":"new-token","expires_in":3600}"#.utf8))
            case "api.php/webasyst.getInfo":
                stub.reply(body: Data(#"{"name":"Recovered"}"#.utf8))
                metadata.fulfill()
            default:
                XCTFail("Unexpected retry request")
                stub.fail(URLError(.unsupportedURL))
            }
        }
        app.retryInstallationAccess(id: "target") { result in
            guard case .success(let install) = result else { return XCTFail("Expected recovery") }
            XCTAssertEqual(install.accessToken, "new-token")
            XCTAssertEqual(app.getUserInstall("target")?.accessToken, "new-token")
            XCTAssertEqual(app.getUserInstall("current")?.accessToken, "cached-token")
            XCTAssertEqual(UserDefaults.standard.string(forKey: "selectDomainUser"), "current")
            recovered.fulfill()
        }
        wait(for: [recovered, metadata], timeout: 5)
        XCTAssertEqual(codeRequests, 2)
        XCTAssertFalse(app.invalidateInstallationAccess(id: "target", rejectedToken: "old-token"))
        XCTAssertEqual(app.getUserInstall("target")?.accessToken, "new-token")
        XCTAssertTrue(app.invalidateInstallationAccess(id: "target", rejectedToken: "new-token"))
        XCTAssertNil(app.getUserInstall("target"))
        XCTAssertEqual(app.getAllUserInstall()?.map(\.id), ["current"])
        XCTAssertEqual(app.getInstallationCatalog()?.map { $0.metadata.id }, ["current", "target"])
        XCTAssertEqual(UserDefaults.standard.string(forKey: "selectDomainUser"), "current")
    }

    func testRemovedInstallationCannotBeRestoredByInFlightRetry() throws {
        seed()
        let app = WebasystApp()
        let catalog = Data(#"[{"id":"target","domain":"target.example.invalid","url":"https://target.example.invalid"}]"#.utf8)
        let first = expectation(description: "initial catalog")
        AuthURLProtocol.handler = { $0.reply(body: catalog) }
        app.userNetworking.getInstallList { _ in first.fulfill() }
        wait(for: [first], timeout: 5)

        let pending = expectation(description: "token request held")
        let discarded = expectation(description: "removed retry completed without saving")
        let empty = expectation(description: "empty catalog")
        var held: AuthURLProtocol?
        AuthURLProtocol.handler = { stub in
            switch self.normalizedPath(stub) {
            case "id/api/v1/auth/client":
                stub.reply(body: Data(#"{"target":"code"}"#.utf8))
            case "api.php/token-headless":
                held = stub
                pending.fulfill()
            case "id/api/v1/installations":
                stub.reply(body: Data("[]".utf8))
            default:
                XCTFail("Unexpected request")
                stub.fail(URLError(.unsupportedURL))
            }
        }
        app.retryInstallationAccess(id: "target") { result in
            if case .success = result { XCTFail("Removed installation cannot open") }
            discarded.fulfill()
        }
        wait(for: [pending], timeout: 5)
        app.updateUserInstalls { result in
            XCTAssertEqual(result?.isEmpty, true)
            empty.fulfill()
        }
        wait(for: [empty, discarded], timeout: 5)
        try XCTUnwrap(held).reply(body: Data(#"{"access_token":"late-token"}"#.utf8))
        let settled = expectation(description: "late response settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 5)
        XCTAssertNil(app.getUserInstall("target"))
        XCTAssertEqual(app.getInstallationCatalog()?.isEmpty, true)
        XCTAssertNil(UserDefaults.standard.string(forKey: "selectDomainUser"))
    }

    func testBackgroundSuccessCannotReplaceExplicitSelectionAfterActiveStoreWasRemoved() throws {
        seed()
        let app = WebasystApp()
        let catalog = Data(#"""
            [{"id":"target","domain":"target.example.invalid","url":"https://target.example.invalid"},
             {"id":"fallback","domain":"fallback.example.invalid","url":"https://fallback.example.invalid"}]
            """#.utf8)
        let removed = "https://removed.example.invalid"
        let fallback = "https://fallback.example.invalid"
        for (id, url) in [("removed", removed), ("fallback", fallback)] {
            XCTAssertTrue(app.profileInstallService?.saveInstall(UserInstall(name: id, domain: id,
                id: id, accessToken: "stored-token", url: url, logoText: "", logoTextColor: "")) == true)
        }
        UserDefaults.standard.set("removed", forKey: "selectDomainUser")
        let loaded = expectation(description: "active store removed")
        AuthURLProtocol.handler = { $0.reply(body: catalog) }
        app.userNetworking.getInstallList { _ in
            XCTAssertNil(app.getUserInstall("removed"))
            XCTAssertEqual(UserDefaults.standard.string(forKey: "selectDomainUser"), "removed")
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 5)

        let targetHeld = expectation(description: "explicit selection waiting")
        let updated = expectation(description: "background fallback available")
        let denied = expectation(description: "explicit failure delivered")
        var exchange: AuthURLProtocol?
        AuthURLProtocol.handler = { stub in
            switch (stub.request.url?.host, self.normalizedPath(stub)) {
            case ("auth.example.invalid", "id/api/v1/installations"):
                stub.reply(body: catalog)
            case ("auth.example.invalid", "id/api/v1/auth/client"):
                stub.reply(body: Data(#"{"target":"target-code","fallback":"fallback-code"}"#.utf8))
            case ("target.example.invalid", "api.php/token-headless"):
                exchange = stub
                targetHeld.fulfill()
            case ("fallback.example.invalid", "api.php/token-headless"):
                stub.reply(body: Data(#"{"access_token":"fallback-token"}"#.utf8))
            case ("fallback.example.invalid", "api.php/webasyst.getInfo"):
                stub.reply(status: 503)
            default:
                XCTFail("Unexpected fixture request")
                stub.fail(URLError(.unsupportedURL))
            }
        }
        app.retryInstallationAccess(id: "target") { result in
            guard case .failure(let error) = result else { return XCTFail("Expected refusal") }
            XCTAssertEqual(error.statusCode, 403)
            XCTAssertEqual(UserDefaults.standard.string(forKey: "selectDomainUser"), "removed")
            denied.fulfill()
        }
        wait(for: [targetHeld], timeout: 5)
        app.updateUserInstalls { _ in
            XCTAssertEqual(app.getUserInstall("fallback")?.accessToken, "fallback-token")
            XCTAssertEqual(UserDefaults.standard.string(forKey: "selectDomainUser"), "removed")
            updated.fulfill()
        }
        wait(for: [updated], timeout: 5)
        try XCTUnwrap(exchange).reply(status: 403, body: Data("<html>Forbidden</html>".utf8))
        wait(for: [denied], timeout: 5)
    }

    func testLoginTimeoutAfterCatalogKeepsAuthorizedSelectionAvailable() throws {
        seed()
        let app = WebasystApp()
        let catalog = Data(#"[{"id":"slow","domain":"slow.example.invalid","url":"https://slow.example.invalid"}]"#.utf8)
        let waiting = expectation(description: "token exchange held")
        let completed = expectation(description: "authorized with catalog after preload deadline")
        var held: AuthURLProtocol?
        AuthURLProtocol.handler = { stub in
            switch self.normalizedPath(stub) {
            case "id/api/v1/installations":
                stub.reply(body: catalog)
            case "id/api/v1/auth/client":
                stub.reply(body: Data(#"{"slow":"code"}"#.utf8))
            case "api.php/token-headless":
                held = stub
                waiting.fulfill()
            default:
                stub.reply(status: 503)
            }
        }
        app.userNetworking.preloadUserData { result in
            switch result {
            case .success(.authorizedButNoneInstalls), .success(.authorizedButNoneInstallsAndProfileIsEmpty):
                break
            default:
                XCTFail("WAID catalog is available even though its exchange is slow")
            }
            XCTAssertEqual(app.getInstallationCatalog()?.map { $0.metadata.id }, ["slow"])
            XCTAssertNil(app.getUserInstall("slow"))
            completed.fulfill()
        }
        wait(for: [waiting, completed], timeout: 18)
        try XCTUnwrap(held).fail(URLError(.timedOut))
    }

    private func normalizedPath(_ stub: AuthURLProtocol) -> String? {
        stub.request.url?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func testBackgroundInstallationRequestCannotUseNewGenerationWithOldCredential() {
        seed()
        let app = WebasystApp()
        let switched = expectation(description: "new session committed between credential read and request")
        let completed = expectation(description: "old installation response rejected")
        keychain.afterAccessRead = {
            DispatchQueue.main.async {
                WebasystAuthSession.shared.beginAuthorization()
                XCTAssertEqual(KeychainManager.savePair(self.pair("new-account")), errSecSuccess)
                app.profileInstallService?.saveInstall(UserInstall(name: "New account", domain: "new.example.invalid",
                    id: "new-install", accessToken: "new-install-token", url: "https://new.example.invalid",
                    image: nil, imageLogo: false, logoText: "", logoTextColor: ""))
                UserDefaults.standard.set("new-install", forKey: "selectDomainUser")
                switched.fulfill()
            }
        }
        AuthURLProtocol.handler = { stub in
            XCTAssertEqual(stub.request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-old")
            XCTAssertEqual(KeychainManager.getToken(.refreshToken), "test-refresh-new-account")
            stub.reply(body: Data("[]".utf8))
        }
        DispatchQueue.global().async {
            app.updateUserInstalls { installs in
                XCTAssertNil(installs, "Old credentials must retain their original generation")
                completed.fulfill()
            }
        }
        wait(for: [switched, completed], timeout: 5)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "selectDomainUser"), "new-install")
        XCTAssertEqual(app.getAllUserInstall()?.map { $0.id }, ["new-install"])
        XCTAssertEqual(KeychainManager.getToken(.refreshToken), "test-refresh-new-account")
    }

    func testFailedKeychainDeletionCannotResurrectLoggedOutSession() {
        seed()
        let revoked = expectation(description: "explicit logout revocation")
        AuthURLProtocol.handler = { stub in stub.reply(status: 204); revoked.fulfill() }
        keychain.deleteFailure = errSecInteractionNotAllowed
        WebasystApp().logOutUser()
        wait(for: [revoked], timeout: 5)
        keychain.deleteFailure = nil
        WebasystAuthSession.shared.invalidate {} // Clear process state without clearing persisted logout.
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-old")
        XCTAssertNil(WebasystApp.getToken(.access))
        XCTAssertNil(WebasystApp.getToken(.refresh))
        let count = AuthURLProtocol.requests.count
        let failed = expectation(description: "logged-out refresh completes locally")
        WebasystApp().refreshAccessToken { XCTAssertFalse($0); failed.fulfill() }
        wait(for: [failed], timeout: 5)
        XCTAssertEqual(AuthURLProtocol.requests.count, count)
        if case .success(false) = KeychainManager.prepareRestoration() {} else { XCTFail("Logout must block restoration") }

        keychain.writeFailureKey = .accessToken
        XCTAssertEqual(KeychainManager.savePair(pair("new")), errSecInteractionNotAllowed)
        XCTAssertNil(WebasystApp.getToken(.refresh), "A partially saved pair must remain blocked")
        keychain.writeFailureKey = nil
        XCTAssertEqual(KeychainManager.savePair(pair("new")), errSecSuccess)
        XCTAssertEqual(WebasystApp.getToken(.refresh), "test-refresh-new")
    }

    func testSeparateWatchTokenWritesDoNotExposeLeftoverCounterpart() {
        seed()
        keychain.deleteFailure = errSecInteractionNotAllowed
        KeychainManager.deleteAll()
        keychain.deleteFailure = nil
        XCTAssertEqual(KeychainManager.save(.accessToken, data: pair("watch").access), errSecSuccess)
        XCTAssertEqual(KeychainManager.getToken(.accessToken), "Bearer test-access-watch")
        XCTAssertEqual(KeychainManager.getToken(.refreshToken), "")
        keychain.writeFailureKey = .refreshToken
        XCTAssertEqual(KeychainManager.save(.refreshToken, data: pair("watch").refresh), errSecInteractionNotAllowed)
        XCTAssertEqual(KeychainManager.getToken(.refreshToken), "")
        keychain.writeFailureKey = nil
        XCTAssertEqual(KeychainManager.save(.refreshToken, data: pair("watch").refresh), errSecSuccess)
        XCTAssertEqual(KeychainManager.getToken(.refreshToken), "test-refresh-watch")
    }

    func testSuccessfulRefreshPreservesLegacyKeysAndNotifications() {
        seed()
        var accessUpdates = 0
        var refreshUpdates = 0
        observe(Notification.Name("accessTokenUpdated")) { _ in accessUpdates += 1 }
        observe(Notification.Name("refreshTokenUpdated")) { _ in refreshUpdates += 1 }
        refresh(expected: true)
        XCTAssertEqual(rawToken(.accessToken), "Bearer test-access-new")
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-new")
        XCTAssertEqual(accessUpdates, 1)
        XCTAssertEqual(refreshUpdates, 1)
    }

    func testHTTPFailuresKeepCurrentCredentials() {
        var logouts = 0
        observe(.webasystDidLoggedOut) { _ in logouts += 1 }
        for status in [400, 401, 403, 404, 429, 500, 502, 503, 504] {
            seed()
            let body = Data(#"{"error":"invalid_client"}"#.utf8)
            refresh(status: status, body: body, expected: false)
            XCTAssertEqual(rawToken(.refreshToken), "test-refresh-old", "HTTP \(status)")
            XCTAssertEqual(rawToken(.accessToken), "Bearer test-access-old", "HTTP \(status)")
        }
        XCTAssertEqual(logouts, 0)
    }

    func testTransportFailuresCompleteAndKeepCredentials() {
        for code in [NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorNotConnectedToInternet,
                     NSURLErrorSecureConnectionFailed, NSURLErrorCancelled] {
            seed()
            refresh(error: NSError(domain: NSURLErrorDomain, code: code), expected: false)
            XCTAssertEqual(rawToken(.refreshToken), "test-refresh-old")
        }
    }

    func testMalformedAndEmptySuccessBodiesKeepCredentials() {
        for body in [Data(), Data("<html>gateway</html>".utf8), Data(#"{"access_token":""}"#.utf8)] {
            seed()
            refresh(body: body, expected: false)
            XCTAssertEqual(rawToken(.refreshToken), "test-refresh-old")
        }
    }

    func testNoNewRefreshTokenRetainsExistingRefreshCredential() {
        seed()
        refresh(body: tokenBody(refresh: false), expected: true)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-old")
        XCTAssertEqual(rawToken(.accessToken), "Bearer test-access-new")
    }

    func testEmptyRefreshTokenIsRejectedWithoutErasingOldPair() {
        seed()
        let body = Data(#"{"access_token":"new","token_type":"bearer","expires_in":3600,"refresh_token":""}"#.utf8)
        refresh(body: body, expected: false)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-old")
    }

    func testDefinitiveRejectionClearsOnlyLocalSessionAndDoesNotRevoke() {
        seed()
        XCTAssertEqual(KeychainManager.store.write(.refreshToken, data: Data("sibling-refresh".utf8), scope: .group), errSecSuccess)
        var logouts = 0
        observe(.webasystDidLoggedOut) { _ in logouts += 1 }
        refresh(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8), expected: false)
        XCTAssertNil(rawToken(.refreshToken))
        XCTAssertEqual(rawToken(.refreshToken, scope: "group"), "sibling-refresh")
        XCTAssertEqual(logouts, 1)
        XCTAssertEqual(AuthURLProtocol.requests.count, 1)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: UserDefaultsKeys.firstLaunch.rawValue))
    }

    func testMalformed401DoesNotSignOut() {
        seed()
        refresh(status: 401, body: Data("<html>denied</html>".utf8), expected: false)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-old")
    }

    func testConcurrentRefreshesAcrossFacadesUseOneRequest() {
        seed()
        let started = expectation(description: "one refresh sent")
        let done = expectation(description: "all callers completed")
        done.expectedFulfillmentCount = 20
        done.assertForOverFulfill = true
        var held: AuthURLProtocol?
        AuthURLProtocol.handler = { stub in held = stub; started.fulfill() }
        for _ in 0..<20 {
            WebasystApp().refreshAccessToken { success in XCTAssertTrue(success); done.fulfill() }
        }
        wait(for: [started], timeout: 5)
        XCTAssertEqual(AuthURLProtocol.requests.count, 1)
        held?.reply(body: tokenBody())
        wait(for: [done], timeout: 5)
        XCTAssertEqual(AuthURLProtocol.requests.count, 1)
    }

    func testConcurrentRejectedRefreshSignsOutOnce() {
        seed()
        let started = expectation(description: "refresh sent")
        let done = expectation(description: "all failures delivered")
        done.expectedFulfillmentCount = 2
        var held: AuthURLProtocol?
        var logouts = 0
        observe(.webasystDidLoggedOut) { _ in logouts += 1 }
        AuthURLProtocol.handler = { held = $0; started.fulfill() }
        for _ in 0..<2 { WebasystApp().refreshAccessToken { XCTAssertFalse($0); done.fulfill() } }
        wait(for: [started], timeout: 5)
        held?.reply(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8))
        wait(for: [done], timeout: 5)
        XCTAssertEqual(logouts, 1)
    }

    func testNewLoginSupersedesOldRefresh() {
        seed()
        let started = expectation(description: "old refresh started")
        let oldDone = expectation(description: "old callback cancelled once")
        let loginDone = expectation(description: "new login completed")
        AuthURLProtocol.handler = { stub in
            if stub.request.url?.path.contains("qr/token") == true { stub.reply(body: self.tokenBody("login")) }
            else { started.fulfill() }
        }
        WebasystApp().refreshAccessToken { XCTAssertFalse($0); oldDone.fulfill() }
        wait(for: [started], timeout: 5)
        WebasystNetworking().sendConfirmCode(for: .qr, "test-code") { XCTAssertTrue($0); loginDone.fulfill() }
        wait(for: [oldDone, loginDone], timeout: 5)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-login")
    }

    func testLateLoginResponseCannotOverwriteNewerLogin() {
        seed()
        let arrived = expectation(description: "two login requests")
        arrived.expectedFulfillmentCount = 2
        let oldDone = expectation(description: "old login refused")
        let newDone = expectation(description: "new login accepted")
        var requests: [AuthURLProtocol] = []
        AuthURLProtocol.handler = { requests.append($0); arrived.fulfill() }
        WebasystNetworking().sendConfirmCode(for: .qr, "old-code") { XCTAssertFalse($0); oldDone.fulfill() }
        WebasystNetworking().sendConfirmCode(for: .qr, "new-code") { XCTAssertTrue($0); newDone.fulfill() }
        wait(for: [arrived], timeout: 5)
        requests[1].reply(body: tokenBody("new-login"))
        wait(for: [newDone], timeout: 5)
        requests[0].reply(body: tokenBody("old-login"))
        wait(for: [oldDone], timeout: 5)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-new-login")
    }

    func testRefreshStartedDuringLoginCannotOverwriteLoginCommit() {
        seed()
        let arrived = expectation(description: "login and refresh requests")
        arrived.expectedFulfillmentCount = 2
        let loginDone = expectation(description: "login done")
        let refreshDone = expectation(description: "refresh cancelled")
        var login: AuthURLProtocol?
        AuthURLProtocol.handler = { stub in
            if stub.request.url?.path.contains("qr/token") == true { login = stub }
            arrived.fulfill()
        }
        WebasystNetworking().sendConfirmCode(for: .qr, "code") { XCTAssertTrue($0); loginDone.fulfill() }
        WebasystApp().refreshAccessToken { XCTAssertFalse($0); refreshDone.fulfill() }
        wait(for: [arrived], timeout: 5)
        login?.reply(body: tokenBody("login"))
        wait(for: [loginDone, refreshDone], timeout: 5)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-login")
    }

    func testManualLogoutInvalidatesPendingRefresh() {
        seed()
        let started = expectation(description: "refresh started")
        let cancelled = expectation(description: "callback completed")
        let revoked = expectation(description: "manual revoke request")
        var logouts = 0
        observe(.webasystDidLoggedOut) { _ in logouts += 1 }
        AuthURLProtocol.handler = { stub in
            if stub.request.httpMethod == "DELETE" { stub.reply(body: Data("{}".utf8)); revoked.fulfill() }
            else { started.fulfill() }
        }
        let app = WebasystApp()
        app.refreshAccessToken { XCTAssertFalse($0); cancelled.fulfill() }
        wait(for: [started], timeout: 5)
        app.logOutUser()
        wait(for: [cancelled, revoked], timeout: 5)
        XCTAssertNil(rawToken(.refreshToken))
        XCTAssertNil(rawToken(.refreshToken, scope: "group"))
        XCTAssertEqual(logouts, 1)
    }

    func testUnauthenticatedStartupCompletesOnceWithoutRefresh() {
        var values: [CheckingType] = []
        WebasystApp().defaultChecking { values.append($0) }
        XCTAssertEqual(values.count, 1)
        guard case .notAuthorized = values[0] else { return XCTFail("Expected welcome") }
        XCTAssertTrue(AuthURLProtocol.requests.isEmpty)
    }

    func testTemporaryKeychainReadFailureDoesNotSignOutOrSendEmptyRefresh() {
        seed()
        keychain.readFailure = errSecInteractionNotAllowed
        var logouts = 0
        observe(.webasystDidLoggedOut) { _ in logouts += 1 }
        var callbacks = 0
        WebasystApp().defaultChecking { status in
            callbacks += 1
            guard case .authorized = status else { return XCTFail("Cached login should be retained") }
        }
        let done = expectation(description: "refresh failure is delivered")
        WebasystApp().refreshAccessToken { XCTAssertFalse($0); done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(logouts, 0)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-old")
        XCTAssertTrue(AuthURLProtocol.requests.isEmpty)
    }

    func testFailedKeychainUpdatePreservesPreviousValue() {
        seed()
        keychain.writeFailureKey = .refreshToken
        XCTAssertEqual(KeychainManager.save(.refreshToken, data: Data("replacement".utf8)), errSecInteractionNotAllowed)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-old")
    }

    func testFailedRefreshPersistenceRetriesSaveWithoutAnotherNetworkRequest() {
        seed()
        keychain.writeFailureKey = .refreshToken
        refresh(expected: false)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-old")
        keychain.writeFailureKey = nil
        let saved = expectation(description: "pending rotated pair saved")
        AuthURLProtocol.handler = { _ in XCTFail("Must not reuse old refresh token") }
        WebasystApp().refreshAccessToken { XCTAssertTrue($0); saved.fulfill() }
        wait(for: [saved], timeout: 5)
        XCTAssertEqual(AuthURLProtocol.requests.count, 1)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-new")
    }

    func testPartialPairSavePreservesRotatedRefreshAndDefersNotifications() {
        seed()
        var updates = 0
        observe(Notification.Name("accessTokenUpdated")) { _ in updates += 1 }
        keychain.writeFailureKey = .accessToken
        refresh(expected: false)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-new")
        XCTAssertEqual(rawToken(.accessToken), "Bearer test-access-old")
        XCTAssertEqual(updates, 0)
        keychain.writeFailureKey = nil
        let saved = expectation(description: "pending pair saved")
        WebasystApp().refreshAccessToken { XCTAssertTrue($0); saved.fulfill() }
        wait(for: [saved], timeout: 5)
        XCTAssertEqual(AuthURLProtocol.requests.count, 1)
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(rawToken(.accessToken), "Bearer test-access-new")
    }

    func testMissingConfigurationAndMissingRefreshComplete() {
        let missing = expectation(description: "missing credentials")
        WebasystApp().refreshAccessToken { XCTAssertFalse($0); missing.fulfill() }
        wait(for: [missing], timeout: 5)
        seed()
        WebasystApp.setConfiguration(nil)
        let config = expectation(description: "missing config")
        WebasystApp().refreshAccessToken { XCTAssertFalse($0); config.fulfill() }
        wait(for: [config], timeout: 5)
        XCTAssertTrue(AuthURLProtocol.requests.isEmpty)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-old")
    }

    func testGeneralRequestRetainsTransportCodeThroughErrorWrapping() {
        let done = expectation(description: "transport failure")
        AuthURLProtocol.handler = { $0.fail(URLError(.cannotFindHost)) }
        WebasystNetworkingManager().createDataTaskSession(URLRequest(url: URL(string: "https://auth.example.invalid/profile")!), generation: WebasystAuthSession.shared.generation) { result in
            guard case .failure(let error) = result else { return XCTFail("Expected failure") }
            let wrapped = WebasystError.getError(ErrorTypeModel(error: error, type: .standart(), methodName: "test"))
            XCTAssertEqual(wrapped.underlyingErrorDomain, NSURLErrorDomain)
            XCTAssertEqual(wrapped.underlyingErrorCode, NSURLErrorCannotFindHost)
            XCTAssertNil(wrapped.statusCode)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testMultipartReplacesExistingContentType() throws {
        var request = URLRequest(url: URL(string: "https://auth.example.invalid/token")!)
        request.setValue("multipart/form-data", forHTTPHeaderField: "Content-Type")
        try request.setMultipartFormData(["code": "test"], encoding: .utf8)
        let content = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertEqual(content.components(separatedBy: "multipart/form-data").count, 2)
        XCTAssertFalse(content.contains(","))
        XCTAssertTrue(content.contains("boundary="))
    }

    func testDiagnosticContainsOnlySanitizedMetadata() {
        seed()
        var events: [[AnyHashable: Any]] = []
        observe(.webasystAuthDiagnostic) { events.append($0.userInfo ?? [:]) }
        refresh(error: URLError(.timedOut), expected: false)
        XCTAssertFalse(events.isEmpty)
        let allowed: Set<String> = ["operation", "outcome", "host", "duration_ms", "reason", "http_status", "error_domain", "error_code"]
        for event in events {
            XCTAssertTrue(Set(event.keys.compactMap { $0 as? String }).isSubset(of: allowed))
            let text = String(describing: event)
            XCTAssertFalse(text.contains("test-refresh"))
            XCTAssertFalse(text.contains("test-access"))
        }
    }
}
