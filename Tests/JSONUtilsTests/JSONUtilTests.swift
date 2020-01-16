//
//  File.swift
//  
//
//  Created by Tobias Haeberle on 16.01.20.
//


import JSONUtils


import XCTest

struct Entry: Codable, Patchable {
    struct Author: Codable {
        var giveName: String?
        var familyName: String?
    }
    var phoneNumber: String?
    var title: String?
    var tags: [String]?
    var content: String?
    var author: Author?
}

final class JSONUtilTests: XCTestCase {
    func testExample() {
        let givenEntry = Entry(phoneNumber: nil, title: "Goodbye!", tags: [ "example", "sample" ], content: "This will be unchanged", author: .init(giveName: "John", familyName: "Doe"))
        
        let patch = """
            {
              "title": "Hello!",
              "phoneNumber": "+01-123-456-7890",
              "author": {
                "familyName": null
              },
              "tags": [ "example" ]
            }
            """.utf8
        
        var patchedEntry = givenEntry
        try! patchedEntry.patch(patch)
        
        print(patchedEntry.toJson())
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}


