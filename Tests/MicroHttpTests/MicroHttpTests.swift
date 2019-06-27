import XCTest
@testable import MicroHttp

final class MicroHttpTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(MicroHttp().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
