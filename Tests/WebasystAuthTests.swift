import XCTest
import Security
@testable import Webasyst

final class WebasystAuthTests: XCTestCase {
    func testTokenResponseWithoutRotationDecodes() throws {
        let body = Data(#"{"access_token":"test-access","token_type":"bearer","expires_in":3600}"#.utf8)
        let token = try JSONDecoder().decode(UserToken.self, from: body)
        XCTAssertNil(token.refresh_token)
    }
}
