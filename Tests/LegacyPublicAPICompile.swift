import UIKit
import Webasyst

// Compiled as an ordinary client, without @testable. This function is deliberately never executed.
func compileLegacyClient(_ app: WebasystApp, navigation: UINavigationController, apple: AuthAppleIDData) {
    app.configure()
    let _: String? = app.getToken(.access)
    let _: String? = app.getToken(.refresh)
    let _: WebasystError = WebasystError(localizedError: "test")
    let _: WebasystError = WebasystError(localizedError: "test", statusCode: 400, errorValue: "test")
    app.refreshAccessToken { (_: Bool) in }
    app.checkUserAuth { (_: WebasystResult<UserStatus>) in }
    app.defaultChecking { value in
        switch value {
        case .authorized, .notAuthorized, .restoredAuthorization, .notRestoredAuthorizaton: break
        }
    }
    app.getAuthCode("test", type: .email) { (_: AuthResult) in }
    app.sendConfirmCode("123456") { (_: Bool) in }
    app.sendConfirmCode(for: .qr, "test") { (_: Bool) in }
    app.oAuthLogin(navigationController: navigation) { (_: WebasystResult<UserStatus>) in }
    app.oAuthAppleID(authData: apple) { (_: AuthAppleIDResult) in }
    app.logOutUser()
}
