//
//  QueryParser.swift
//  MicroHttp
//
//  Created by Tobias Haeberle on 27.06.19.
//

import Foundation

private let queryKey = "microhttp.queryParser.query"
private let componentsKey = "microhttp.queryParser.urlComponents"

public let queryParser: Middleware = { req, res, ctx in
    let components = URLComponents(string: req.header.uri)
    req.userInfo[componentsKey] = components
    req.userInfo[queryKey] = components?.queryItems?.reduce(into: [String: [String]](), {params, item in
        guard let value = item.value else { return }
        if params[item.name] == nil {
            params[item.name] = [ value ]
        } else {
            params[item.name]!.append(value)
        }
    })
    ctx.next()
}

extension IncommingMessage {
    public var query: [String: [String]]? {
        return self.userInfo[queryKey] as? [String: [String]]
    }
    
    public var components: URLComponents? { return self.userInfo[componentsKey] as? URLComponents }
    
    public func parameter<R: LosslessStringConvertible>(_ named: String, of type: R.Type = R.self) -> R? {
        return self.query?[named]?.first.flatMap { R($0) }
    }
}
