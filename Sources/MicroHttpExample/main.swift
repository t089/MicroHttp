import NIO
import MicroHttp
import Prometheus
import Metrics
import NIOSSL
import Logging

let prometheus = PrometheusMetrics()

LoggingSystem.bootstrap(StreamLogHandler.standardError)
MetricsSystem.bootstrap(prometheus)

let app = MicroApp()

app.use(metrics)
app.use(logger(.debug))

app.get("/hello") { (_, res, ctx) in
    res.status(.ok).send("Hello").end()
}


app.get("/long") { (_, res, ctx) in
    res.status = .ok
    _ = res.send("Request recieved. will wait a bit... press ctr-c now or run this command\n\n")
    _ = res.send("    kill -INT \(getpid())\n")
    ctx.eventLoop.scheduleTask(in: .seconds(30), { () -> () in
        res.send("still here :)").end()
    })
}

app.post("/bin") { (req, res, ctx) in
    let body = req.body.consume()
    
    body.whenSuccess({ (body) in
        res.status(.ok).send("got \(body.readableBytes) bytes.\n").end()
    })
    
    body.whenFailure { (error) in
        res.status(.payloadTooLarge).send("Body too large").end()
    }
}

app.get("/metrics") { (_, res, ctx) in
    res.send(prometheus.export()).end()
}

let certificateChain = try! NIOSSLCertificate.fromPEMFile("/Users/tobias/Developing/swift-maps/cert.pem")
let sslContext = try! NIOSSLContext(configuration: TLSConfiguration.forServer(certificateChain: certificateChain.map { .certificate($0) }, privateKey: .file("/Users/tobias/Developing/swift-maps/key.pem")))


let otherDomain = Router()
otherDomain.get("/hello") { (_, res, ctx) in
    res.status = .ok
    res.send("Hello from other domain.").end()
}


app.listen(host: "::1", port: 8080)

try? app.fullySutdownFuture?.wait()
