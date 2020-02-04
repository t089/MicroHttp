import XCTest

import JSONUtilsTests
import MicroHttpTests

var tests = [XCTestCaseEntry]()
tests += JSONUtilsTests.__allTests()
tests += MicroHttpTests.__allTests()

XCTMain(tests)
