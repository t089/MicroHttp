//
//  File.swift
//  
//
//  Created by Tobias Haeberle on 16.01.20.
//

import Foundation



public struct JSONMergePatch: CustomStringConvertible {
    public typealias Encoder<T: Codable> = (T) throws -> Data
    public typealias Decoder<T: Codable> = (Data) throws -> T
    
    public struct Codec<T: Codable> {
        public let encode: Encoder<T>
        public let decode: Decoder<T>
        
        public static func jsonEncoder(_ configure: (JSONEncoder) -> () = { _ in }) -> Encoder<T> {
            let encoder = JSONEncoder()
            configure(encoder)
            return { try encoder.encode($0) }
        }
        
        public static func jsonDecoder(_ configure: (JSONDecoder) -> () = { _ in }) -> Decoder<T> {
            let decoder = JSONDecoder()
            configure(decoder)
            return { try decoder.decode(T.self, from: $0) }
        }
        
        public init(encode: @escaping Encoder<T> = Codec<T>.jsonEncoder(), decode: @escaping Decoder<T> = Codec<T>.jsonDecoder()) {
            self.encode = encode
            self.decode = decode
        }
        
        func toJson(_ value: T) throws -> Any {
            let data = try encode(value)
            return try JSONSerialization.jsonObject(with: data, options: [])
        }
        
        func fromJson(_ json: Any) throws -> T {
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            return try decode(data)
        }
    }
    
    private let json: Any
    
    private init(json: Any) {
        self.json = json
    }
    
    public init(data: Data) throws {
        self.json = try JSONSerialization.jsonObject(with: data, options: [ .allowFragments ])
    }
    
    public static func from<T: Codable>(original: T, to new: T, codec: Codec<T> = Codec()) throws -> JSONMergePatch {
        return try JSONMergePatch(json: JSONUtils.mergePatch(from: codec.toJson(original), to:  codec.toJson(new)))
    }
    
    public func apply<T: Codable>(to target: T, codec: Codec<T> = Codec()) throws -> T {
        let new = try JSONUtils.mergePatch(target: codec.toJson(target), patch: json)
        return try codec.fromJson(new)
    }
    
    public var description: String {
        return String(decoding: try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]), as: UTF8.self)
    }
}

fileprivate func mergePatch(target: Any, patch: Any) -> Any {
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

fileprivate func jsonEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    switch (lhs, rhs) {
    case (let lhs as NSNumber, let rhs as NSNumber):
        return lhs.isEqual(to: rhs)
    case (let lhs as NSString, let rhs as NSString):
        return lhs.isEqual(to: rhs)
    case ( _ as NSNull,  _ as NSNull):
        return true
    case(let lhs as NSArray, let rhs as NSArray):
        return lhs.isEqual(to: rhs)
    case (let lhs as NSDictionary, let rhs as NSDictionary):
        return lhs.isEqual(to: rhs)
    default:
        return false
    }
}

fileprivate func mergePatch(from source: Any, to target: Any) -> Any {
    if let source = source as? [String: Any] {
        if let target = target as? [String: Any] {
            var patch = [String: Any?]()
            for (key, value) in target {
                if source[key] == nil {
                    patch[key] = value
                } else if let sourceObj = source[key] as? [String: Any], let targetObj = value as? [String: Any] {
                    let newValue = mergePatch(from: sourceObj, to: targetObj) as! [String: Any]
                    if !newValue.isEmpty {
                        patch[key] = newValue
                    }
                } else if jsonEqual(source[key] as Any, value) == false {
                    patch[key] = value
                }
            }
            
            let missingKeysInTarget = Set(source.keys).subtracting(target.keys)
            for missingKey in missingKeysInTarget {
                patch[missingKey] = Optional(.none)
            }
            return patch
        } else {
            return target
        }
    } else {
        return target
    }
}
