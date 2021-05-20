import XCTest
import Webasyst

class Tests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        WebasystApp.configure(clientId: "96fa27732ea21b508a24f8599168ed49", host: "www.webasyst.com", scope: "blog,site,shop,webasyst")
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
}
