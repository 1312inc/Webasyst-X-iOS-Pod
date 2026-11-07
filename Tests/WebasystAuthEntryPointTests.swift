import XCTest
import Security
@testable import Webasyst

private final class AuthDelegateProbe: AuthCoordinatorDelegate {
    var onError: ((WebasystError) -> Void)?
    func successAuth(_ status: UserStatus) { XCTFail("Unexpected successful authorization") }
    func errorAuth(_ error: WebasystError) { onError?(error) }
}

final class WebasystAuthEntryPointTests: AuthTestCase {
    private var appleData: AuthAppleIDData {
        AuthAppleIDData(userIdentifier: "test-user", authorizationCode: "test-code", identityToken: "test-identity",
            isRealUserStatus: true, userFirstName: nil, userLastName: nil, userEmail: nil)
    }

    func testOAuthScreenKeepsActualKeychainTransportAndServerFailure() {
        for kind in ["keychain", "transport", "server", "decoding", "invalidCode"] {
            keychain.writeFailureKey = nil
            seed()
            keychain.writeFailureKey = kind == "keychain" ? .refreshToken : nil
            keychain.writeFailure = errSecMissingEntitlement
            let done = expectation(description: "OAuth screen failure: " + kind)
            let delegate = AuthDelegateProbe()
            delegate.onError = { error in
                switch kind {
                case "keychain":
                    XCTAssertEqual(error.underlyingErrorDomain, NSOSStatusErrorDomain)
                    XCTAssertEqual(error.underlyingErrorCode, Int(errSecMissingEntitlement))
                    XCTAssertTrue(error.localizedError.contains(WebasystApp.getDefaultLocalizedString(withKey: "error.keychainSave")))
                case "transport":
                    XCTAssertEqual(error.underlyingErrorDomain, NSURLErrorDomain)
                    XCTAssertEqual(error.underlyingErrorCode, NSURLErrorTimedOut)
                case "server": XCTAssertEqual(error.statusCode, 503)
                case "invalidCode":
                    XCTAssertEqual(error.statusCode, 400)
                    XCTAssertEqual(error.errorValue, "invalid_grant")
                default:
                    XCTAssertEqual(error.statusCode, 200)
                    XCTAssertTrue(error.localizedError.contains(WebasystApp.getDefaultLocalizedString(withKey: "unableToDecodeResponsedData")))
                }
                done.fulfill()
            }
            AuthURLProtocol.handler = { stub in
                switch kind {
                case "transport": stub.fail(URLError(.timedOut))
                case "server": stub.reply(status: 503, body: Data("{}".utf8))
                case "invalidCode": stub.reply(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8))
                case "decoding": stub.reply(body: Data("{}".utf8))
                default: stub.reply(body: self.tokenBody("oauth"))
                }
            }
            let model = AuthViewModel(networkingService: WebasystNetworking(), delegate: delegate, with: "")
            model.successAuth(code: "oauth-code", state: "state")
            withExtendedLifetime(model) { wait(for: [done], timeout: 5) }
            XCTAssertEqual(KeychainManager.getToken(.refreshToken), "test-refresh-old")
        }
    }

    func testAppleIDServerErrorPreservesExistingOAuthMetadata() {
        let done = expectation(description: "Apple error value retained")
        AuthURLProtocol.handler = { $0.reply(status: 400, body: Data(#"{"error":"invalid_client"}"#.utf8)) }
        WebasystApp().oAuthAppleID(authData: appleData) { result in
            guard case .completed(.error(let error)) = result else { return XCTFail("Expected Apple ID error") }
            XCTAssertEqual(error.errorValue, "invalid_client")
            XCTAssertEqual(error.statusCode, 400)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testTemporaryPublicFacadeDeliversPhoneAndAppleCallbacks() {
        let phone = expectation(description: "temporary facade phone code")
        AuthURLProtocol.handler = { $0.reply(body: Data("{}".utf8)) }
        WebasystApp().getAuthCode("test@example.invalid", type: .email) { result in
            if case .success = result {} else { XCTFail("Expected sent code") }
            phone.fulfill()
        }
        wait(for: [phone], timeout: 5)

        let apple = expectation(description: "temporary facade Apple ID failure")
        AuthURLProtocol.handler = { $0.fail(URLError(.timedOut)) }
        WebasystApp().oAuthAppleID(authData: appleData) { result in
            guard case .completed(.error(let error)) = result else { return XCTFail("Expected Apple transport error") }
            XCTAssertEqual(error.underlyingErrorCode, NSURLErrorTimedOut)
            apple.fulfill()
        }
        wait(for: [apple], timeout: 5)
    }

    func testOldAppleConfirmationCannotReplaceOrLogOutNewAccount() throws {
        let received = expectation(description: "old Apple confirmation handler")
        var handler: ((AuthAppleIDResult.EmailConfirmation) -> Void)?
        AuthURLProtocol.handler = {
            $0.reply(body: Data(#"{"access_token":"temporary-email-token","token_type":"bearer","expires_in":3600,"email_confirm":true}"#.utf8))
        }
        WebasystApp().oAuthAppleID(authData: appleData) { result in
            if case .needEmailConfirmation(_, let confirmation) = result { handler = confirmation }
            else { XCTFail("Expected email confirmation") }
            received.fulfill()
        }
        wait(for: [received], timeout: 5)
        let newLogin = expectation(description: "new QR login")
        AuthURLProtocol.handler = { $0.reply(body: self.tokenBody("other-account")) }
        WebasystNetworking().sendConfirmCode(for: .qr, "other-account") { XCTAssertTrue($0); newLogin.fulfill() }
        wait(for: [newLogin], timeout: 5)
        let requestCount = AuthURLProtocol.requests.count
        let confirmation = try XCTUnwrap(handler)
        for action in [AuthAppleIDResult.EmailConfirmation.Result.code("123456"), .logout] {
            let done = expectation(description: "stale handler rejected")
            confirmation(.init(action) { success, error in
                XCTAssertFalse(success)
                XCTAssertNotNil(error)
                done.fulfill()
            })
            wait(for: [done], timeout: 5)
            XCTAssertEqual(KeychainManager.getToken(.refreshToken), "test-refresh-other-account")
            XCTAssertEqual(AuthURLProtocol.requests.count, requestCount)
        }
    }

    func testDiagnosticObserverLogoutCannotCreateUsableAppleConfirmation() {
        seed()
        let completed = expectation(description: "reentrant logout rejects Apple response")
        let revoked = expectation(description: "reentrant explicit logout revokes old credentials")
        observe(.webasystAuthDiagnostic) { notification in
            guard notification.userInfo?["operation"] as? String == "appleID",
                  notification.userInfo?["outcome"] as? String == "received" else { return }
            WebasystApp().logOutUser()
        }
        AuthURLProtocol.handler = { stub in
            if stub.request.url?.path.contains("apple") == true {
                stub.reply(body: Data(#"{"access_token":"temporary-email-token","token_type":"bearer","expires_in":3600,"email_confirm":true}"#.utf8))
            } else { stub.reply(status: 204); revoked.fulfill() }
        }
        WebasystApp().oAuthAppleID(authData: appleData) { result in
            if case .completed(.error) = result {} else { XCTFail("Logout must supersede the temporary Apple response") }
            completed.fulfill()
        }
        wait(for: [completed, revoked], timeout: 5)
        XCTAssertNil(WebasystApp.getToken(.access))
        XCTAssertNil(WebasystApp.getToken(.refresh))
    }

    func testRefreshOnlyLegacySessionSurvivesMigrationFailureThenRestores() {
        var query = rawQuery(.refreshToken, scope: "past")
        query.removeValue(forKey: kSecReturnData as String)
        query.removeValue(forKey: kSecMatchLimit as String)
        query[kSecValueData as String] = pair("legacy-only").refresh
        XCTAssertEqual(keychain.system.add(query), errSecSuccess)
        keychain.writeFailureKey = .refreshToken
        if case .success = KeychainManager.prepareRestoration() { XCTFail("Expected migration write failure") }
        XCTAssertEqual(rawToken(.refreshToken, scope: "past"), "test-refresh-legacy-only")
        keychain.writeFailureKey = nil
        let restored = expectation(description: "legacy refresh restores access")
        observe(Notification.Name("refreshTokenUpdated")) { _ in
            if self.rawToken(.refreshToken) == "test-refresh-restored-legacy" { restored.fulfill() }
        }
        AuthURLProtocol.handler = { stub in
            if stub.request.url?.path == "/id/oauth2/auth/token" { stub.reply(body: self.tokenBody("restored-legacy")) }
            else { stub.reply(body: Data((stub.request.url?.path.contains("installations") == true ? "[]" : "{}").utf8)) }
        }
        WebasystApp().defaultChecking { result in
            if case .authorized = result {} else { XCTFail("Legacy refresh must allow cached startup") }
        }
        wait(for: [restored], timeout: 5)
        XCTAssertEqual(KeychainManager.getToken(.accessToken), "Bearer test-access-restored-legacy")
        XCTAssertNil(rawToken(.refreshToken, scope: "past"))
    }

    func testOAuthExchangeTransportFailureCompletes() {
        let networking = WebasystNetworking()
        XCTAssertNotNil(networking.buildAuthRequest(""))
        let done = expectation(description: "OAuth failure completes")
        AuthURLProtocol.handler = { $0.fail(URLError(.timedOut)) }
        networking.getAccessToken("code", stateString: "state") { XCTAssertFalse($0); done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    func testOAuthExchangeSuccessUsesLegacyStorage() {
        let networking = WebasystNetworking()
        XCTAssertNotNil(networking.buildAuthRequest(""))
        let done = expectation(description: "OAuth succeeds")
        AuthURLProtocol.handler = { $0.reply(body: self.tokenBody("oauth")) }
        networking.getAccessToken("code", stateString: "state") { XCTAssertTrue($0); done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-oauth")
    }

    func testPhoneCodeSuccessAndKeychainFailureBothComplete() {
        let networking = WebasystNetworking()
        XCTAssertNotNil(networking.buildAuthRequest(""))
        for failure in [false, true] {
            keychain.writeFailureKey = failure ? .refreshToken : nil
            let done = expectation(description: "SMS completion")
            AuthURLProtocol.handler = { $0.reply(body: self.tokenBody("sms")) }
            networking.sendConfirmCode(for: .phone, "123456") { XCTAssertEqual($0, !failure); done.fulfill() }
            wait(for: [done], timeout: 5)
        }
    }

    func testQRStorageFailureCompletesWithoutDeletingExistingCredentials() {
        seed()
        keychain.writeFailureKey = .refreshToken
        let done = expectation(description: "QR failure completes")
        AuthURLProtocol.handler = { $0.reply(body: self.tokenBody("qr")) }
        WebasystNetworking().sendConfirmCode(for: .qr, "code") { XCTAssertFalse($0); done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-old")
    }

    func testAppleIDSuccessAndFailureComplete() {
        for failure in [false, true] {
            let done = expectation(description: "Apple ID completes")
            AuthURLProtocol.handler = { stub in
                if failure { stub.fail(URLError(.secureConnectionFailed)) }
                else { stub.reply(body: self.tokenBody("apple")) }
            }
            WebasystNetworking().oAuthAppleID(authData: appleData) { result in
                switch result {
                case .success(.succeess): XCTAssertFalse(failure)
                case .error(let error):
                    XCTAssertTrue(failure)
                    XCTAssertEqual(error.underlyingErrorCode, NSURLErrorSecureConnectionFailed)
                default: XCTFail("Unexpected email confirmation")
                }
                done.fulfill()
            }
            wait(for: [done], timeout: 5)
        }
    }

    func testAppleEmailConfirmationDoesNotReplaceSessionUntilConfirmed() throws {
        seed()
        let received = expectation(description: "email confirmation required")
        var temporary: Data?
        let body = Data(#"{"access_token":"temporary-email-token","token_type":"bearer","expires_in":3600,"email_confirm":true}"#.utf8)
        AuthURLProtocol.handler = { $0.reply(body: body) }
        WebasystNetworking().oAuthAppleID(authData: appleData) { result in
            if case .success(.needEmailConfirmation(let token)) = result { temporary = token }
            else { XCTFail("Expected email confirmation") }
            received.fulfill()
        }
        wait(for: [received], timeout: 5)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-old")
        let confirmed = expectation(description: "email confirmed")
        AuthURLProtocol.handler = { $0.reply(body: self.tokenBody("confirmed")) }
        WebasystUserNetworking().sendAppleIDEmailConfirmationCode("123456", accessToken: try XCTUnwrap(temporary)) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            confirmed.fulfill()
        }
        wait(for: [confirmed], timeout: 5)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-confirmed")
    }

    func testAppleEmailStorageFailureCompletes() {
        seed()
        keychain.writeFailureKey = .refreshToken
        let done = expectation(description: "email storage failure")
        AuthURLProtocol.handler = { $0.reply(body: self.tokenBody()) }
        WebasystUserNetworking().sendAppleIDEmailConfirmationCode("123456", accessToken: Data("Bearer temporary".utf8)) { result in
            guard case .failure(let error) = result else { return XCTFail("Expected storage failure") }
            XCTAssertEqual(error.underlyingErrorCode, Int(errSecInteractionNotAllowed))
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testSharedRestorationUsesSharedAccessWithoutCopyingForeignRefresh() {
        XCTAssertEqual(KeychainManager.store.write(.accessToken, data: Data("Bearer shared-access".utf8), scope: .group), errSecSuccess)
        XCTAssertEqual(KeychainManager.store.write(.refreshToken, data: Data("foreign-client-refresh".utf8), scope: .group), errSecSuccess)
        guard case .success(true) = KeychainManager.prepareRestoration() else { return XCTFail("Restoration expected") }
        XCTAssertNil(rawToken(.refreshToken))
        let done = expectation(description: "cross-app exchange")
        AuthURLProtocol.handler = { stub in
            XCTAssertEqual(stub.request.value(forHTTPHeaderField: "Authorization"), "Bearer shared-access")
            XCTAssertNil(self.rawToken(.refreshToken))
            stub.reply(body: self.tokenBody("restored"))
        }
        WebasystUserNetworking().restoreTokensFromGroup { XCTAssertTrue($0); done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-restored")
    }

    func testSharedRestorationFailurePreservesSharedCredentialAndCompletesStartup() {
        XCTAssertEqual(KeychainManager.store.write(.accessToken, data: Data("Bearer shared-access".utf8), scope: .group), errSecSuccess)
        let done = expectation(description: "startup restored failure")
        AuthURLProtocol.handler = { $0.fail(URLError(.timedOut)) }
        WebasystApp().defaultChecking { result in
            if case .notRestoredAuthorizaton = result {} else { XCTFail("Expected failed restoration") }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(rawToken(.accessToken, scope: "group"), "Bearer shared-access")
        XCTAssertNil(rawToken(.refreshToken))
    }

    func testSharedRestorationStorageFailureCompletes() {
        XCTAssertEqual(KeychainManager.store.write(.accessToken, data: Data("Bearer shared".utf8), scope: .group), errSecSuccess)
        keychain.writeFailureKey = .refreshToken
        let done = expectation(description: "cross-app storage failure")
        AuthURLProtocol.handler = { $0.reply(body: self.tokenBody("restored")) }
        WebasystUserNetworking().restoreTokensFromGroup { XCTAssertFalse($0); done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertNil(rawToken(.refreshToken))
        XCTAssertEqual(rawToken(.accessToken, scope: "group"), "Bearer shared")
    }

    func testOldLegacyCredentialsMigrateOnlyAfterSuccessfulNativeWrite() {
        for key in [KeychainEnum.accessToken, .refreshToken] {
            var query = rawQuery(key, scope: "past")
            query.removeValue(forKey: kSecReturnData as String)
            query.removeValue(forKey: kSecMatchLimit as String)
            query[kSecValueData as String] = key == .accessToken ? pair("legacy").access : pair("legacy").refresh
            XCTAssertEqual(keychain.system.add(query), errSecSuccess)
        }
        keychain.writeFailureKey = .refreshToken
        if case .success = KeychainManager.prepareRestoration() { XCTFail("Expected write failure") }
        XCTAssertEqual(rawToken(.refreshToken, scope: "past"), "test-refresh-legacy")
        keychain.writeFailureKey = nil
        guard case .success(false) = KeychainManager.prepareRestoration() else { return XCTFail("Migration expected") }
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-legacy")
        XCTAssertNil(rawToken(.refreshToken, scope: "past"))
    }

    func testEmptyInstallationListCompletesInsteadOfHanging() {
        let done = expectation(description: "zero installations")
        WebasystUserNetworking().getAccessTokenInstall([], accessCodes: [:]) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertTrue(AuthURLProtocol.requests.isEmpty)
    }

    func testMissingInstallationCodeCompletesInsteadOfCrashing() {
        let done = expectation(description: "missing installation code")
        let install = UserInstallCodable(name: nil, domain: "example.invalid", id: "test", accessToken: nil,
            url: "https://installation.example.invalid", image: nil)
        WebasystUserNetworking().getAccessTokenInstall([install], accessCodes: [:]) { result in
            guard case .failure = result else { return XCTFail("Missing code must fail") }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testPreloadWithNoInstallationsCompletes() {
        seed()
        let done = expectation(description: "preload completes")
        AuthURLProtocol.handler = { stub in
            let body = stub.request.url?.path.contains("installations") == true ? Data("[]".utf8) : Data("{}".utf8)
            stub.reply(body: body)
        }
        WebasystUserNetworking().preloadUserData { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testPreloadTimeoutCompletesOnceAndStopsLaterInstallationRequests() throws {
        seed()
        let request = expectation(description: "profile request held")
        let timedOut = expectation(description: "preload timeout")
        timedOut.assertForOverFulfill = true
        var held: AuthURLProtocol?
        var completions = 0
        AuthURLProtocol.handler = { stub in held = stub; request.fulfill() }
        let networking = WebasystUserNetworking()
        networking.preloadUserData { result in
            completions += 1
            guard case .failure(let error) = result else { return XCTFail("Expected preload timeout") }
            XCTAssertEqual(error.underlyingErrorCode, NSURLErrorTimedOut)
            timedOut.fulfill()
        }
        wait(for: [request, timedOut], timeout: 18)
        try XCTUnwrap(held).reply(status: 503, body: Data("{}".utf8))
        let settled = expectation(description: "late response settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(AuthURLProtocol.requests.count, 1)
        XCTAssertEqual(KeychainManager.getToken(.refreshToken), "test-refresh-old")
    }

    func testDelayedProfileImageCannotOverwriteNewSession() throws {
        seed()
        let imageRequest = expectation(description: "old profile image held")
        let completed = expectation(description: "stale profile operation completes")
        var image: AuthURLProtocol?
        let body = Data(#"{"name":"Old","firstname":"Old","lastname":"Account","middlename":"","email":[],"phone":[],"userpic_original_crop":"https://images.example.invalid/old"}"#.utf8)
        AuthURLProtocol.handler = { stub in
            if stub.request.url?.host == "images.example.invalid" { image = stub; imageRequest.fulfill() }
            else { stub.reply(body: body) }
        }
        let profile = ProfileData(name: "Old", firstname: "Old", lastname: "Account", middlename: "",
                                  email: "", phone: "", userpic_original_crop: nil)
        let app = WebasystApp()
        app.changeCurrentUserData(profile: profile) { result in
            if case .success = result { XCTFail("Old profile operation must be rejected") }
            completed.fulfill()
        }
        wait(for: [imageRequest], timeout: 5)
        WebasystAuthSession.shared.beginAuthorization()
        XCTAssertEqual(KeychainManager.savePair(pair("new-account")), errSecSuccess)
        try XCTUnwrap(image).reply(body: Data("old-image".utf8))
        wait(for: [completed], timeout: 5)
        XCTAssertNil(app.getProfileData())
        XCTAssertEqual(KeychainManager.getToken(.refreshToken), "test-refresh-new-account")
    }

    func testProtectedRequest401DoesNotDestroyRefreshCredential() {
        seed()
        let done = expectation(description: "protected request error")
        AuthURLProtocol.handler = { stub in
            if stub.request.url?.path == "/id/oauth2/auth/token" { stub.reply(body: self.tokenBody()) }
            else { stub.reply(status: 401, body: Data(#"{"error":"invalid_token"}"#.utf8)) }
        }
        WebasystApp().checkUserAuth { result in
            guard case .failure(let error) = result else { return XCTFail("Expected protected-resource failure") }
            XCTAssertEqual(error.statusCode, 401)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(rawToken(.refreshToken), "test-refresh-new")
    }
}
