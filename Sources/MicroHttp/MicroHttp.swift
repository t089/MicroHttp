import NIO
import NIOHTTP1
import Metrics

open class MicroApp: Router {
    public let group: EventLoopGroup
	public private(set) var serverChannel: Channel!
    
    public init(group: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)) {
        self.group = group
    }
    
    open func listen(host: String, port: Int, backlog: CInt = 256) {
		let bootstrap = ServerBootstrap(group: self.group)
	    // Specify backlog and enable SO_REUSEADDR for the server itself
	    .serverChannelOption(ChannelOptions.backlog, value: backlog)
	    .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
	    
	    // Set the handlers that are applied to the accepted Channels
	    .childChannelInitializer { channel in
	        /* channel.pipeline.addHandler(DebugOutboundEventsHandler())
	         .flatMap { */
	        channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true)
	            .flatMap {
	                channel.pipeline.addHandler(HTTPHandler(router: self))
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
		} catch {
			fatalError("Failed to start server: \(error)")
		}
	}
}


public let metrics: Middleware = { req, res, ctx in
    res.whenComplete { r in
        switch r {
        case .success:
            Counter(label: "http_requests_total", dimensions: [
                ( "route", req.header.uri ),
                ("method", req.header.method.rawValue),
                ("status", "\(res.status.code)") ]).increment()
        case .failure:
            Counter(label: "http_requests_total", dimensions: [
                ( "route", req.header.uri ),
                ("method", req.header.method.rawValue),
                ("status", "error") ]).increment()
        }
    }
    
    ctx.next()
}
