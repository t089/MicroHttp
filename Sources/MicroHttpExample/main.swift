
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


app.get("/metrics") { (_, res, ctx) in
    res.send(prometheus.export()).end()
}

app.listen(host: "localhost", port: 8080)

try? app.serverChannel.closeFuture.wait()
