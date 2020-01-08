//
//  Networking.swift
//  resized
//
//  Created by Tobias Haeberle on 18.06.19.
//

import NIO
import NIOHTTP1
import Metrics

public final class IncommingMessage {
    public let header: HTTPRequestHead
    public var userInfo: [String: Any] = [:]
    
    public let body: Body
    
    init(header: HTTPRequestHead, body: Body) {
        self.header = header
        self.body = body
    }
    
    public final class Body {
        var buffer: ByteBuffer
        
        let bodyCompletePromise: EventLoopPromise<Void>
        
        init(buffer: ByteBuffer, bodyCompletePromise: EventLoopPromise<Void>) {
            self.buffer = buffer
            self.bodyCompletePromise = bodyCompletePromise
        }
        
        public func consume() -> EventLoopFuture<ByteBuffer> {
            return self.bodyCompletePromise.futureResult.map {
                return self.buffer
            }
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

public final class BodyStream {
    public enum StreamError: Error {
        case alreadySubscribed
    }
    
    public enum Event {
        case part(ByteBuffer)
        case failure(Error)
        case finished
    }
    
    public let eventLoop: EventLoop
    public typealias Consumer = (Event, @escaping () -> ()) -> ()
    
    private var buffer: ByteBuffer
    
    private let _channelRead: () -> ()
    
    init(eventLoop: EventLoop, buffer: ByteBuffer, channelRead: @escaping () -> ()) {
        self.eventLoop = eventLoop
        self._channelRead = channelRead
        self.buffer = buffer
    }
    
    var consumer: Consumer?
    private var inputClosed: Result<Void, Error>?
    
    private var waitingForNextReadOfConsumer: Bool = false
    
    private func read() {
        // print("consumer called read")
        if self.eventLoop.inEventLoop {
            self.read0()
        } else {
            self.eventLoop.execute {
                self.read0()
            }
        }
    }
    
    private func read0() {
        precondition(self.consumer != nil)
        // first drain the buffer
        self.waitingForNextReadOfConsumer = false
        
        if self.buffer.readableBytes > 0 {
            // print("draining read buffer")
            let copy = self.buffer
            self.buffer.clear()
            self.waitingForNextReadOfConsumer = true
            self.consumer?(.part(copy), self.read)
        } else if let closed = self.inputClosed {
            // print("input was already closed")
            // if the input was already closed relay to consumer
            switch closed {
            case .success(_):
                self.consumer?(.finished, { /* */ })
            case .failure(let err):
                self.consumer?(.failure(err), { /* */ })
            }
            self.consumer = nil
        } else {
            // print("reading from channel")
            // read from the channel
            self._channelRead()
        }
    }
    
    func send0(_ event: Event) {
        // print("received event: \(event)")
        if let consumer = self.consumer, self.waitingForNextReadOfConsumer == false {
            // print("directly forwaring to consumer")
            switch event {
            case .part(let buffer):
                self.waitingForNextReadOfConsumer = true
                consumer(.part(buffer), self.read)
            case .failure(let e):
                self.inputClosed = .failure(e)
                self.consumer = nil
                consumer(.failure(e), { /* */})
            case .finished:
                self.inputClosed = .success(())
                self.consumer = nil
                consumer(.finished, { /* */})
            }
        } else {
            // print("consumer is not ready, buffering")
            switch event {
            case .part(var b): self.buffer.writeBuffer(&b)
            case .finished:
                self.inputClosed = .success(())
            case .failure(let e):
                self.inputClosed = .failure(e)
            }
        }
    }
    
    
    
    public func consume(_ consumer: @escaping Consumer) {
        if self.eventLoop.inEventLoop {
            self.consume0(consumer)
        } else {
            self.eventLoop.execute {
                self.consume0(consumer)
            }
        }
    }
    
    private func consume0(_ consumer: @escaping Consumer) {
        assert(self.consumer == nil, "Tried to consume body more than once.")
        guard self.consumer == nil else { _ = consumer(.failure(StreamError.alreadySubscribed), { /* */ }); return }
        
        // print("Start consuming body")
        
        self.consumer = consumer
        
        // start reading from buffer or socket
        self.read0()
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
    private var bodyCompletePromise: EventLoopPromise<Void>?
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        
        switch reqPart {
        case .head(let head):
//            self.start = .now()
            self.buffer.clear()
            let bodyCompletePromise = context.eventLoop.makePromise(of: Void.self)
            self.bodyCompletePromise = bodyCompletePromise
            let req = IncommingMessage(header: head, body: .init(buffer: self.buffer, bodyCompletePromise: bodyCompletePromise))
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
        case .body(var body):
            self.request.body.buffer.writeBuffer(&body)
        case .end(_):
            self.request.body.bodyCompletePromise.succeed(())
            
            self.request = nil
            self.bodyCompletePromise = nil
        }
    }
    
    func handlerAdded(context: ChannelHandlerContext) {
        
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.buffer.clear()
        self.request = nil
        self.bodyCompletePromise = nil
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        // print("Channel inactive")
        self.buffer.clear()
        self.request = nil
        self.bodyCompletePromise = nil
    }
    
}
