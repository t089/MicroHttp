//
//  File.swift
//  
//
//  Created by Tobias Haeberle on 16.01.20.
//

import Foundation



public func mergePatch(target: Any, patch: Any) -> Any {
    if let patch = patch as? [String: Any?] {
        var patchedTarget: [String: Any] = [:]
        if let target = target as? [String: Any] {
            patchedTarget = target
        }
        
        for (key, value) in patch {
            if (value == nil) {
                patchedTarget[key] = nil
            } else {
                patchedTarget[key] = mergePatch(target: patchedTarget[key] as Any, patch: value as Any)
            }
        }
        return patchedTarget
    } else {
        return patch
    }
}

func jsonEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    switch (lhs, rhs) {
    case (let lhs as NSNumber, let rhs as NSNumber):
        return lhs.isEqual(to: rhs)
    case (let lhs as NSString, let rhs as NSString):
        return lhs.isEqual(to: rhs)
    case (let lhs as NSNull, let rhs as NSNull):
        return true
    case(let lhs as NSNull, _):
        return rhs == nil
    case(_, let rhs as NSNull):
        return lhs == nil
    case(let lhs as NSArray, let rhs as NSArray):
        return lhs.isEqual(to: rhs)
//        guard lhs.count == rhs.count else { return false }
//        for (idx, val) in lhs.enumerated() {
//            if (jsonEqual(lhs.object(at: idx), rhs.object(at: idx)) == false) {
//                return false
//            }
//        }
//        return true
    case (let lhs as NSDictionary, let rhs as NSDictionary):
        return lhs.isEqual(to: rhs)
    default:
        return false
    }
}

public func mergePatch(from source: Any, to target: Any) -> Any {
    if let source = source as? [String: Any] {
        if let target = target as? [String: Any] {
            var patch = [String: Any?]()
            for (key, value) in target {
                if source[key] == nil {
                    patch[key] = value
                } else if let sourceObj = source[key] as? [String: Any], let targetObj = value as? [String: Any] {
                    patch[key]  = mergePatch(from: sourceObj, to: targetObj)
                }
            }
            
            let missingKeysInTarget = Set(source.keys).subtracting(target.keys)
            for missingKey in missingKeysInTarget {
                patch[missingKey] = Optional(nil)
            }
        } else {
            return target
        }
    } else {
        return target
    }
}

public func asJsonString(_ json: Any) -> String {
    return String(decoding: try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]), as: UTF8.self)
}

extension Encodable {
    public func toJson(encoder: (Self) throws -> Data = JSONEncoder().encode) -> Any {
        let data = try! encoder(self)
        return try! JSONSerialization.jsonObject(with: data, options: [])
    }
}

extension Decodable {
    public static func fromJson(_ json: Any, decoder: (Data) throws -> Self = { return try JSONDecoder().decode(Self.self, from: $0) }) throws -> Self {
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        return try decoder(data)
    }
}

public protocol Patchable: Encodable, Decodable {
    mutating func patch<JSON: Sequence>(_ patch: JSON) throws  where JSON.Element == UInt8
    
    func patch(from other: Self) throws -> Data
}

extension Patchable {
    public mutating func patch<JSON: Sequence>(_ patch: JSON) throws where JSON.Element == UInt8 {
        let patchJson = try JSONSerialization.jsonObject(with: Data(patch), options: [])
        let patched = mergePatch(target: self.toJson(), patch: patchJson)
        self = try Self.fromJson(patched)
    }
    
    public func patch(from other: Self) throws -> Data {
        let originalJson = other.toJson()
        let newJson      = self.toJson()
    }
}

extension Sequence where Element == UInt8 {
    public var json: Any {
        return try! JSONSerialization.jsonObject(with: Data(self), options: [])
    }
}
