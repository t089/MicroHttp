import Foundation
import Logging

public let logger: (Logger.Level) -> Middleware = { level in
    return { req, res, ctx in
        var logger = Logger(label: "micro_http")
        logger.logLevel = level
        let requestId = UUID()
        logger[metadataKey: "request_id"] = .string(requestId.uuidString.lowercased())
        logger[metadataKey: "request_uri"] = .string(req.header.uri)
        logger[metadataKey: "request_method"] = .string(req.header.method.rawValue)
        let headers = req.header.headers.reduce(into: [String: Logger.MetadataValue](), { result, header in
            result[header.name] = .string(header.value)
        })
        logger[metadataKey: "request_headers"] = .dictionary( headers )
        if let remote = res.channel.remoteAddress {
            logger[metadataKey: "remote_address"] = .string("\(remote)")
        }
        
        req.userInfo["logger"] = logger
        
        let start = Date()
        res.whenComplete { result in
            let elapsed = Date().timeIntervalSince(start)
            let meta = ["request_elapsed": Logger.MetadataValue.string("\(elapsed)")]
            switch result {
            case .success:
                logger.info("\(req.header.method.rawValue) \(req.header.uri) - \(res.status.code) - \(elapsed)s", metadata: meta)
            case .failure(let e):
                logger.error("\(req.header.method.rawValue) \(req.header.uri) - \(e) - \(elapsed)s", metadata: meta)
            }
        }
        
        ctx.next()
    }
}

extension IncommingMessage {
    public var logger: Logger! {
        return self.userInfo["logger"] as? Logger
    }
}
