
import CoreMetrics
import Cmetrics
import NIOConcurrencyHelpers

/// `PrometheusClient` is a metrics backend for `SwiftMetrics`, designed to integrate applications with observability servers that support `statsd` protocol.
/// The client uses `SwiftNIO` to establish a UDP connection to the `statsd` server.
public final class PrometheusMetrics: MetricsFactory {
    private var counters = [PrometheusUtils.Id: PrometheusCounter]() // protected by a lock
    private var recorders = [PrometheusUtils.Id: PrometheusRecorder]() // protected by a lock
    private var timers = [PrometheusUtils.Id: PrometheusTimer]() // protected by a lock
    private let lock = Lock()
    
    /// Create a new instance of `PrometheusMetrics`
    ///
    /// - parameters:
    ///     - eventLoopGroupProvider: The `EventLoopGroupProvider` to use, uses`createNew` strategy by default.
    ///     - host: The `statsd` server host.
    ///     - port: The `statsd` server port.
    public init() {
       
    }
    
    private let cpu_info = cpu_info_new()
    
    deinit {
        cpu_info_free(self.cpu_info)
    }
    
    public func export() -> String {
        
        var counters  : [PrometheusUtils.Id: PrometheusCounter]!
        var recorders : [PrometheusUtils.Id: PrometheusRecorder]!
        var timers    : [PrometheusUtils.Id: PrometheusTimer]!
        
        
        var cpu : Double = 0
        
        self.lock.withLockVoid {
            counters = self.counters
            recorders = self.recorders
            timers = self.timers
            
            cpu = cpu_info_get_current_usage(self.cpu_info)
        }
        
        var result = ""
        
        let mem = getCurrentRSS()
        result.append("process_resident_memory_bytes \(mem)\n")
        result.append("process_cpu_used_ratio \(cpu)\n")
        
        
        for (id, counter) in counters {
            result.append("\(id.prometheusRepresentation) \(counter.value.load())\n")
        }
        
        return result
    }
    
    // MARK: - SwiftMetric.MetricsFactory implementation
    
    public func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
        let maker = { (label: String, dimensions: [(String, String)]) -> PrometheusCounter in
            PrometheusCounter(label: label, dimensions: dimensions)
        }
        return self.lock.withLock {
            self.make(label: label, dimensions: dimensions, registry: &self.counters, maker: maker)
        }
    }
    
    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler {
        let maker = { (label: String, dimensions: [(String, String)]) -> PrometheusRecorder in
            PrometheusRecorder(label: label, dimensions: dimensions, aggregate: aggregate)
        }
        return self.lock.withLock {
            self.make(label: label, dimensions: dimensions, registry: &self.recorders, maker: maker)
        }
    }
    
    public func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
        let maker = { (label: String, dimensions: [(String, String)]) -> PrometheusTimer in
            PrometheusTimer(label: label, dimensions: dimensions)
        }
        return self.lock.withLock {
            self.make(label: label, dimensions: dimensions, registry: &self.timers, maker: maker)
        }
    }
    
    private func make<Item>(label: String, dimensions: [(String, String)], registry: inout [PrometheusUtils.Id: Item], maker: (String, [(String, String)]) -> Item) -> Item {
        let id = PrometheusUtils.id(label: label, dimensions: dimensions)
        if let item = registry[id] {
            return item
        }
        let item = maker(label, dimensions)
        registry[id] = item
        return item
    }
    
    public func destroyCounter(_ handler: CounterHandler) {
        if let counter = handler as? PrometheusCounter {
            self.lock.withLockVoid {
                self.counters.removeValue(forKey: counter.id)
            }
        }
    }
    
    public func destroyRecorder(_ handler: RecorderHandler) {
        if let recorder = handler as? PrometheusRecorder {
            self.lock.withLockVoid {
                self.recorders.removeValue(forKey: recorder.id)
            }
        }
    }
    
    public func destroyTimer(_ handler: TimerHandler) {
        if let timer = handler as? PrometheusTimer {
            self.lock.withLockVoid {
                self.timers.removeValue(forKey: timer.id)
            }
        }
    }
}

// MARK: - SwiftMetric.Counter implementation



private final class PrometheusCounter: CounterHandler, Equatable {
    let id: PrometheusUtils.Id
    var value = Atomic<Int64>(value: 0)
    
    init(label: String, dimensions: [(String, String)]) {
        self.id = PrometheusUtils.id(label: label, dimensions: dimensions)
    }
    
    public func increment(by amount: Int64) {
        self._increment(by: amount)
    }
    
    private func _increment(by amount: Int64) {
        while true {
            let oldValue = self.value.load()
            guard oldValue != Int64.max else {
                return // already at max
            }
            let newValue = oldValue.addingReportingOverflow(amount)
            if self.value.compareAndExchange(expected: oldValue, desired: newValue.overflow ? Int64.max : newValue.partialValue) {
                return
            }
        }
    }
    
    public func reset() {
        self.value.store(0)
    }
    
    public static func == (lhs: PrometheusCounter, rhs: PrometheusCounter) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - SwiftMetric.Recorder implementation

private final class PrometheusRecorder: RecorderHandler, Equatable {
    let id: PrometheusUtils.Id
    let aggregate: Bool
    
    private var measurements: [Double] {
        return self.lock.withLock {
            return self._measurements
        }
    }
    
    private var _measurements: [Double] = []
    let lock = Lock()
    
    init(label: String, dimensions: [(String, String)], aggregate: Bool) {
        self.id = PrometheusUtils.id(label: label, dimensions: dimensions)
        self.aggregate = aggregate
    }
    
    func record(_ value: Int64) {
        self.lock.withLockVoid {
            self._measurements.append(Double(value))
        }
    }
    
    func record(_ value: Double) {
        self.lock.withLockVoid {
            self._measurements.append(Double(value))
        }
    }
    
    public static func == (lhs: PrometheusRecorder, rhs: PrometheusRecorder) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - SwiftMetric.Timer implementation

private final class PrometheusTimer: TimerHandler, Equatable {
    let id: PrometheusUtils.Id
    
    private var measurements: [Int64] {
        return self.lock.withLock {
            return self._measurements
        }
    }
    private var _measurements: [Int64] = []
    let lock = Lock()
    
    init(label: String, dimensions: [(String, String)]) {
        self.id = PrometheusUtils.id(label: label, dimensions: dimensions)
    }
    
    public func recordNanoseconds(_ duration: Int64) {
        self.lock.withLockVoid {
            self._measurements.append(duration)
        }
    }
    
    public static func == (lhs: PrometheusTimer, rhs: PrometheusTimer) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Utility

private enum PrometheusUtils {
    struct Id: Equatable, Hashable {
        let label: String
        let dimensions: [(String, String)]
        
        var prometheusRepresentation: String {
            if dimensions.isEmpty {
                return label
            }
            
            let labels = self.dimensions.reduce(into: [String](), { $0.append("\($1.0)=\($1.1)") }).joined(separator: ", ")
            return "\(label){\(labels)}"
        }
        
        static func ==(lhs: Id, rhs: Id) -> Bool {
            guard lhs.label == rhs.label else { return false }
            guard lhs.dimensions.count == rhs.dimensions.count else { return false }
            
            for (l,r) in zip(lhs.dimensions.lazy, rhs.dimensions.lazy) {
                guard l.0 == r.0 else { return false }
                guard l.1 == r.1 else { return false }
            }
            
            return true
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(self.label)
            for d in self.dimensions {
                hasher.combine(d.0)
                hasher.combine(d.1)
            }
        }
    }
    
    static func id(label: String, dimensions: [(String, String)]) -> Id {
        return Id(label: label, dimensions: dimensions)
    }
}
