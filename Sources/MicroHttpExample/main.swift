import NIO
import MicroHttp
import Prometheus
import Metrics

let prometheus = PrometheusMetrics()

MetricsSystem.bootstrap(prometheus)

let app = MicroApp()

app.use(metrics)

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
    req.body.consume().whenSuccess({ (body) in
        res.status(.ok).send("got \(body.readableBytes) bytes.\n").end()
    })
}

app.get("/metrics") { (_, res, ctx) in
    res.send(prometheus.export()).end()
}

app.listen(host: "localhost", port: 0)

try? app.fullySutdownFuture?.wait()
