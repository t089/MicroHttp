import NIO
import NIOHTTP1
import Metrics
import NIOExtras
import Foundation
import NIOSSL
import NIOTLS

open class MicroApp: Router {
    public let group: EventLoopGroup
	
    private var serverChannel: Channel!
    private var quiesce: ServerQuiescingHelper?
    private var fullyShutdownPromise: EventLoopPromise<Void>?
    
    public var fullySutdownFuture: EventLoopFuture<Void>? { return self.fullyShutdownPromise?.futureResult }
    
    public init(group: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)) {
        self.group = group
    }
    
    open func listen(host: String, port: Int, backlog: CInt = 256, sslHandler: [String: (NIOSSLContext, Router)] = [:]) {

        
        self.quiesce = ServerQuiescingHelper(group: self.group)
		let bootstrap = ServerBootstrap(group: self.group)
	    // Specify backlog and enable SO_REUSEADDR for the server itself
	    .serverChannelOption(ChannelOptions.backlog, value: backlog)
	    .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .serverChannelInitializer({ (channel) -> EventLoopFuture<Void> in
                channel.pipeline.addHandler(self.quiesce!.makeServerChannelHandler(channel: channel))
            })
	    // Set the handlers that are applied to the accepted Channels
	    .childChannelInitializer { channel in
	        /* channel.pipeline.addHandler(DebugOutboundEventsHandler())
	         .flatMap { */
            
            func configureHttp(handler: HTTPHandler) -> EventLoopFuture<Void> {
                return channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true)
                    .flatMap {
                        channel.pipeline.addHandler(handler)
                }
            }
            
            if (sslHandler.isEmpty == false) {
                return channel.pipeline.addHandler(ByteToMessageHandler(SNIHandler(sniCompleteHandler: { (result) -> EventLoopFuture<Void> in
                    
                    switch result {
                    case .hostname(let hostname):
                        print("wants hostname: \(hostname)")
                        guard let config = sslHandler[hostname] else {
                            print("hostname \(hostname) not supported")
                            fallthrough
                        }
                        
                        return channel.pipeline.addHandler(try! NIOSSLServerHandler(context: config.0)).flatMap {
                            return configureHttp(handler: .init(router: config.1))
                        }
                    default:
                        print("No hostname determined use default SSL cert.")
                        return channel.close()
                    }
                })))
            } else {
                return configureHttp(handler: .init(router: self))
            }
	    }
	    
	    // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
	    .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
        .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
	    .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

	    do {
			let channel = try bootstrap.bind(host:host, port: port).wait()
			self.serverChannel = channel
			print("Server listening on: \(channel.localAddress!)")
            self.fullyShutdownPromise = self.group.next().makePromise(of: Void.self)
            self.installSignalHandler(quiesce: self.quiesce!)
		} catch {
			fatalError("Failed to start server: \(error)")
		}
	}
    
    public func shutdown() {
        self.quiesce?.initiateShutdown(promise: self.fullyShutdownPromise)
    }
    
    let signalQueue = DispatchQueue(label: "MicroHttp.SignalHandlingQueue")
    
    private func installSignalHandler(quiesce: ServerQuiescingHelper) {
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: self.signalQueue)
        signalSource.setEventHandler {
            signalSource.cancel()
            print("\nShutting down...")
            quiesce.initiateShutdown(promise: self.fullyShutdownPromise)
            self.installForceShutdownSignalHandler()
        }
        signal(SIGINT, SIG_IGN)
        signalSource.resume()
    }
    
    private func installForceShutdownSignalHandler() {
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: self.signalQueue)
        signalSource.setEventHandler {
            signalSource.cancel()
            print("\nExiting.")
            exit(0)
        }
        signal(SIGINT, SIG_IGN)
        signalSource.resume()
    }
}


public let metrics: Middleware = { req, res, ctx in
    res.whenComplete { r in
        switch r {
        case .success:
            Counter(label: "http_requests_total", dimensions: [
                ( "route", req.header.path ),
                ("method", req.header.method.rawValue),
                ("status", "\(res.status.code)") ]).increment()
        case .failure:
            Counter(label: "http_requests_total", dimensions: [
                ( "route", req.header.path ),
                ("method", req.header.method.rawValue),
                ("status", "error") ]).increment()
        }
    }
    
    ctx.next()
}


extension HTTPRequestHead {
    var path: String {
        guard let idx = self.uri.firstIndex(of: "?") else { return self.uri }
        return String(self.uri[self.uri.startIndex..<idx])
    }
}
