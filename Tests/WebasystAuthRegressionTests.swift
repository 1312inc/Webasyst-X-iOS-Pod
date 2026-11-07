import XCTest
import Security
@testable import Webasyst

final class WebasystAuthRegressionTests: AuthTestCase {
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
