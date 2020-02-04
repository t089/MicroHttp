//
//  File.swift
//  
//
//  Created by Tobias Haeberle on 16.01.20.
//


import JSONUtils


import XCTest

struct Entry: Codable, Equatable {
    struct Author: Codable, Equatable {
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
    let givenEntry = Entry(phoneNumber: nil, title: "Goodbye!", tags: [ "example", "sample" ], content: "This will be unchanged", author: .init(giveName: "John", familyName: "Doe"))
    
    func testExample() {
        
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
        
        let patchedEntry = try! JSONMergePatch(data: Data(patch)).apply(to: givenEntry)
        
        print(patchedEntry)
    }
    
    func testMakePatch() throws {
        let originalEntry = givenEntry
        var modifiedEntry = originalEntry
        modifiedEntry.author?.familyName = "Müller"
        modifiedEntry.author?.giveName = nil

        modifiedEntry.tags = [ "hot" ]
        modifiedEntry.title = nil
        
        let patch = try JSONMergePatch.from(original: originalEntry, to: modifiedEntry)
        
        print("Patch: \(patch)")
        
        let patchedEntry = try patch.apply(to: originalEntry)
        
        print(patchedEntry)
        
        XCTAssertEqual(patchedEntry, modifiedEntry)
    }

    static var allTests = [
        ("testExample", testExample),
        ("testMakePatch", testMakePatch)
    ]
}

extension Sequence where Element == UInt8 {
    var prettyPrintedJson: String {
        let obj = try! JSONSerialization.jsonObject(with: Data(self), options: [])
        let pretty = try! JSONSerialization.data(withJSONObject: obj, options: [ .prettyPrinted ])
        return String(decoding: pretty, as: UTF8.self)
    }
}

