//
//  File.swift
//  
//
//  Created by Tobias on 17.01.20.
//

import Foundation

/// A type-safe wrapper around JSON data
public enum JSON {
  case object([String: JSON])
  case array([JSON])
  case integer(Int64)
  case double(Double)
  case string(String)
  case boolean(Bool)
  case null
}

extension JSON: Equatable {}
public func ==(lhs: JSON, rhs: JSON) -> Bool {
  switch (lhs,rhs) {
  case (.null, .null):
    return true
  case let (.boolean(l), .boolean(r)):
    return l == r
  case let (.string(l), .string(r)):
    return l == r
  case let (.integer(l), .integer(r)):
    return l == r
  case let (.double(l), .double(r)):
    return l == r
  case let (.array(l), .array(r)):
    return l == r
  case let (.object(l), .object(r)):
    return l == r
  default:
    return false
  }
}

extension JSON {
    public func toNative() -> Any {
        switch self {
        case .null:
            return NSNull()
        case .boolean(let b):
            return NSNumber(value: b)
        case .double(let dbl):
            return NSNumber(value: dbl)
        case .integer(let int):
            return NSNumber(value: int)
        case .string(let str):
            return NSString(string: str)
        case .array(let array):
            let result = NSMutableArray()
            for element in array {
                result.add(element.toNative())
            }
            return result.copy() as! NSArray
        case .object(let obj):
            let out = NSMutableDictionary()
            for (k, v) in obj { out.setObject(v.toNative(), forKey: NSString(string: k)) }
            return out.copy() as! NSDictionary
        }
    }
}