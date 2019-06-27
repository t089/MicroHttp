import XCTest

import MicroHttpTests

var tests = [XCTestCaseEntry]()
tests += MicroHttpTests.allTests()
XCTMain(tests)
