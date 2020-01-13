//
//  Networking.swift
//  resized
//
//  Created by Tobias Haeberle on 18.06.19.
//

import NIO
import NIOHTTP1
import Metrics

public enum BodyStreamResult {
    case buffer(ByteBuffer)
    case end
    case error(Error)
}

final class BodyStream {
    typealias Handler = (BodyStreamResult, EventLoopPromise<Void>?) -> ()
    private(set) var  isClosed : Bool
    
    let eventLoop: EventLoop
    
    private var buffer: [(BodyStreamResult, EventLoopPromise<Void>?)]
    private var handler: Handler?
    
    init(eventLoop: EventLoop) {
        self.buffer = []
        self.isClosed = false
        self.eventLoop = eventLoop
    }
    
    func read(_ handler: @escaping Handler) {
        self.handler = handler
        for (result, promise) in self.buffer {
            handler(result, promise)
        }
        self.buffer = []
    }
    
    func write(part: BodyStreamResult, promise: EventLoopPromise<Void>?) {
        if case .end = part {
            self.isClosed = true
        }
        
        if let handler = self.handler {
            handler(part, promise)
        } else {
            self.buffer.append((part, promise))
        }
    }
    
    func write(part: BodyStreamResult) -> EventLoopFuture<Void> {
        let p = self.eventLoop.makePromise(of: Void.self)
        self.write(part: part, promise: p)
        return p.futureResult
    }
}



public final class IncommingMessage {
    public let header: HTTPRequestHead
    public var userInfo: [String: Any] = [:]
    
    let bodyStream: BodyStream
    
    init(header: HTTPRequestHead, bodyStream: BodyStream) {
        self.header = header
        self.bodyStream = bodyStream
    }
    
    public var body: Body {
        return Body(msg: self)
    }
    
    public struct Body {
        let msg: IncommingMessage
        
        struct BodyTooLargeError: Error {}
        
        public func consume(limit: UInt32 = 1_024 * 1_024 * 2) -> EventLoopFuture<ByteBuffer> {
            let contentLength = self.msg.header.headers["content-length"].first.flatMap(UInt32.init) ?? limit
            var buffer = ByteBufferAllocator().buffer(capacity: Int(min(contentLength, limit)))
            let p = self.msg.bodyStream.eventLoop.makePromise(of: ByteBuffer.self)
            self.msg.bodyStream.read { (res, rp) in
                switch res {
                case .buffer(var part):
                    guard (part.readableBytes + buffer.readableBytes <= limit) else {
                        rp?.fail(BodyTooLargeError())
                        p.fail(BodyTooLargeError())
                        return
                    }
                    buffer.writeBuffer(&part)
                    rp?.succeed(())
                case .end:
                    p.succeed(buffer)
                    rp?.succeed(())
                case .error(let err):
                    p.fail(err)
                    rp?.fail(err)
                }
            }
            return p.futureResult
        }
    }
}



public final class ServerResponse {
    public  var status         = HTTPResponseStatus.ok
    public  var headers        = HTTPHeaders()
    public let channel: Channel
    public var remoteAdress: SocketAddress? { return self.channel.remoteAddress }
    
    private var didSendHeaders: Bool = false
    
    private let complete: EventLoopPromise<Void>
    public func whenComplete(_ completion: @escaping (Result<Void, Error>) -> ()) {
        self.complete.futureResult.whenComplete(completion)
    }
    
    
    private func flushHeaders() {
        guard self.didSendHeaders == false else { return }
        defer { self.didSendHeaders = true }
        
        self.channel.writeAndFlush(HTTPServerResponsePart.head(.init(version: .init(major: 1, minor: 1), status: self.status, headers: self.headers))).whenFailure { (error) in
            print("Error flushing headers: \(error)")
        }
        
    }
    
    init(channel: Channel) {
        self.channel = channel
        self.complete = self.channel.eventLoop.makePromise()
    }
    
    @discardableResult
    public func status(_ status: HTTPResponseStatus) -> Self {
        self.status = status
        return self
    }
    
    public func send() -> Self {
        self.flushHeaders()
        return self
    }
    
    public func end(_ trailing: HTTPHeaders? = nil, promise: EventLoopPromise<Void>? = nil) {
        self.channel.writeAndFlush(HTTPServerResponsePart.end(trailing), promise: self.complete)
        self.complete.futureResult.cascade(to: promise)
    }
    
    public func send(_ message: String, promise: EventLoopPromise<Void>? = nil) -> Self {
        self.flushHeaders()
        var buffer = self.channel.allocator.buffer(capacity: message.count)
        buffer.writeString(message)
        self.channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: promise)
        return self
    }
    
    public func send<Bytes: Sequence>(_ data: Bytes, promise: EventLoopPromise<Void>? = nil) -> ServerResponse where Bytes.Element == UInt8  {
        self.flushHeaders()
        var buffer = self.channel.allocator.buffer(capacity: data.underestimatedCount)
        buffer.writeBytes(data)
        self.channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: promise)
        return self
    }
}

extension EventLoopPromise {
    func resolve(_ result: Result<Value, Error>) {
        switch result {
        case .success(let v): self.succeed(v)
        case .failure(let e): self.fail(e)
        }
    }
}

public protocol MiddlewareProtocol {
    func handle(error: Error?,
                request req: IncommingMessage,
                response res: ServerResponse,
                context ctx: Context) throws
}

public typealias Next = (Error?) -> ()
public typealias Middleware = (IncommingMessage, ServerResponse, Context) throws -> ()
public typealias ErrorMiddleware = (Error, IncommingMessage, ServerResponse, Context) throws -> ()


public struct Context {
    public let eventLoop: EventLoop
    private let next: Next
    
    public func next(_ error: Error? = nil) {
        if self.eventLoop.inEventLoop {
            self.next(error)
        } else {
            self.eventLoop.execute {
                self.next(error)
            }
        }
    }
    
    public init(eventLoop: EventLoop, next: @escaping Next) {
        self.eventLoop = eventLoop
        self.next = next
    }
}





public struct Abort: Error {
    public var status: HTTPResponseStatus
    public var message: String?
    
    public init(_ status: HTTPResponseStatus, message: String? = nil) {
        self.status = status
        self.message = message
    }
}

enum SomeMiddleware: MiddlewareProtocol {
    case middlewareImpl(MiddlewareProtocol)
    case middleware(Middleware)
    case error(ErrorMiddleware)
    
    @inlinable
    func handle(error: Error?, request req: IncommingMessage, response res: ServerResponse, context ctx: Context) throws {
        switch self {
        case .middlewareImpl(let impl):
            try impl.handle(error: error, request: req, response: res, context: ctx)
        case .middleware(let mw):
            guard error == nil else { return ctx.next(error) }
            try mw(req, res, ctx)
        case .error(let mw):
            guard let error = error else { return ctx.next() }
            try mw(error, req, res, ctx)
        }
    }
}

open class Router {
    private var middlewares: [SomeMiddleware] = []
    
    public init() {}
    
    open func use<Middleware: MiddlewareProtocol>(_ middleware: Middleware) {
        self.middlewares.append(.middlewareImpl(middleware))
    }
    
    open func use(_ middlewares: Middleware...) {
        self.middlewares.append(contentsOf: middlewares.map { .middleware($0) })
    }
    
    open func use(_ middlewares: ErrorMiddleware...) {
        self.middlewares.append(contentsOf: middlewares.map { .error($0)} )
    }
    
    open func use(_ path: String, middleware: @escaping Middleware) {
        self.use { (req, res, ctx) in
            if req.header.uri.hasPrefix(path) {
                try middleware(req, res, ctx)
            } else {
                ctx.next()
            }
        }
    }
    
    open func use(_ method: HTTPMethod, _ path: String, middleware: @escaping Middleware) {
        self.use { (req, res, ctx) in
            if req.header.method == method && req.header.uri.hasPrefix(path) {
                try middleware(req, res, ctx)
            } else {
                ctx.next()
            }
        }
    }
    
    open func post(_ path: String, middleware: @escaping Middleware) {
        self.use(.POST, path, middleware: middleware)
    }
    
    open func get(_ path: String, middleware: @escaping Middleware) {
        self.use(.GET, path, middleware: middleware)
    }
    
    func handle(error: Error?,
                request: IncommingMessage,
                response: ServerResponse,
                context ctx: Context) {
        var stack = self.middlewares[self.middlewares.indices]
        var lastContext: Context? = ctx
        
        func step(_ error: Error? = nil) {
            let context = Context(eventLoop: ctx.eventLoop, next: step)
            if let middleware = stack.popFirst() {
                do {
                    try middleware.handle(error: error, request: request, response: response, context: context)
                } catch {
                    step(error)
                }
            } else {
                lastContext?.next(error); lastContext = nil
            }
        }
        
        step()
    }
}



final class HTTPHandler: ChannelInboundHandler , ChannelOutboundHandler {
    private var mayRead = true
    private var pendingRead = false
    
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart
    typealias OutboundIn = HTTPServerResponsePart
    
    private(set) var router: Router
    
    init(router: Router) {
        self.router = router
    }
    
    private enum State {
        case idle
        case head(ServerResponse, bodyConsumed: Bool, responseSent: Bool)
        
        mutating func responseComplete() {
            switch self {
            case .head(let res, bodyConsumed: let bodyConsumed, responseSent: let responseSent):
                assert(responseSent == false)
                if bodyConsumed {
                    self = .idle
                } else {
                    self = .head(res, bodyConsumed: bodyConsumed, responseSent: true)
                }
            default:
                break; //assertionFailure("wrong state for responseComplete: \(self)")
            }
        }
        
        
        
        mutating func readBody() {
            switch self {
            case let .head(_, bodyConsumed: bodyConsumed, responseSent: _):
                assert(bodyConsumed == false)
            default:
                break; // assertionFailure("wrong state for readBody: \(self)")
            }
        }
        
        mutating func bodyConsumed() {
            switch self {
            case .head(let res, bodyConsumed: let bodyConsumed, responseSent: let responseSent):
                assert(bodyConsumed == false)
                if responseSent {
                    self = .idle
                } else {
                    self = .head(res, bodyConsumed: true, responseSent: responseSent)
                }
            default:
                break; // assertionFailure("wrong state for bodyConsumed: \(self)")
            }
        }
        
    }
    
    private var buffer = ByteBufferAllocator().buffer(capacity: 4096 * 1024)
    private var start: NIODeadline = .now()
    
    private var request: IncommingMessage!
    
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        
        switch reqPart {
        case .head(let head):
//            self.start = .now()
            self.buffer.clear()
            
            let bodyStream = BodyStream(eventLoop: context.eventLoop)
            let req = IncommingMessage(header: head, bodyStream: bodyStream)
            let res = ServerResponse(channel: context.channel)
            self.request = req
            self.router.handle(error: nil, request: req, response: res, context: .init(eventLoop: context.eventLoop, next: { (error) in
                if let error = error {
                    res.status = .internalServerError
                    let msg = "unhandled error: \(error)"
                    res.send(msg).end()
                    // print(msg)
                } else {
                    res.status = .notFound
                    res.send("No middleware handled the request.").end()
                }
            }))
        case .body(let body):
            self.request.bodyStream.write(part: .buffer(body), promise: nil)
        case .end(_):
            self.request.bodyStream.write(part: .end, promise: nil)
            
            self.request = nil
            
        }
    }
    
    func read(context: ChannelHandlerContext) {
        if (self.pendingWrites <= 0) {
            context.read()
        } else {
            self.pendingRead = true
        }
    }
    
    private var pendingWrites = 0
    private func write(part: BodyStreamResult, to stream: BodyStream, context: ChannelHandlerContext) {
        self.pendingWrites += 1
        stream.write(part: part).whenComplete { (result) in
            self.pendingWrites -= 1
            if (self.pendingRead == true) {
                self.pendingRead = false
                self.read(context: context)
            }
        }
    }
    
    func handlerAdded(context: ChannelHandlerContext) {
        
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.buffer.clear()
        self.request?.bodyStream.write(part: .error(error), promise: nil)
        self.request = nil
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        // print("Channel inactive")
        self.buffer.clear()
        self.request = nil
    }
    
}
