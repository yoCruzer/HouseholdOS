import XCTest
@testable import HouseholdOSApp

final class HouseholdOSAppTests: XCTestCase {
    func testAppModuleLoads() {
        XCTAssertEqual(String(describing: RootView.self), "RootView")
    }
}
