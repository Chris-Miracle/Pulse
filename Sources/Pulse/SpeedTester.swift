import Foundation

/// Thread-safe byte counter fed by URLSession delegate callbacks.
final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n: Int64 = 0
    func add(_ v: Int64) { lock.lock(); n += v; lock.unlock() }
    var total: Int64 { lock.lock(); defer { lock.unlock() }; return n }
}

/// Runs N parallel streams and keeps them alive (restarting finished ones) until stopped.
final class Transfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let counter = ByteCounter()
    private let lock = NSLock()
    private var running = true
    var makeTask: ((URLSession) -> URLSessionTask)?

    private(set) lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.httpMaximumConnectionsPerHost = 8
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    func start(streams: Int) {
        for _ in 0..<streams { makeTask?(session).resume() }
    }

    func stop() {
        lock.lock(); running = false; lock.unlock()
        session.invalidateAndCancel()
    }

    private var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        counter.add(Int64(data.count))
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        counter.add(bytesSent)
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Stream finished early on a fast link: start another so the pipe stays full.
        guard error == nil, isRunning, let make = makeTask else { return }
        make(s).resume()
    }
}

enum SpeedTestError: LocalizedError {
    case noData
    var errorDescription: String? { "No data received. Check your connection." }
}

@MainActor
final class SpeedTester: ObservableObject {
    enum Phase: Equatable {
        case idle, latency, download, upload, done
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var liveMbps: Double = 0
    @Published private(set) var downloadMbps: Double?
    @Published private(set) var uploadMbps: Double?
    @Published private(set) var latencyMs: Double?
    @Published private(set) var jitterMs: Double?

    private var task: Task<Void, Never>?

    var isRunning: Bool {
        switch phase {
        case .latency, .download, .upload: return true
        default: return false
        }
    }

    func start() {
        guard !isRunning else { return }
        downloadMbps = nil; uploadMbps = nil; latencyMs = nil; jitterMs = nil; liveMbps = 0
        task = Task { await run() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
        liveMbps = 0
    }

    private func run() async {
        do {
            phase = .latency
            let (lat, jit) = try await Self.measureLatency()
            latencyMs = lat; jitterMs = jit

            phase = .download
            downloadMbps = try await Self.measure(upload: false) { [weak self] mbps in
                Task { @MainActor in self?.liveMbps = mbps }
            }

            liveMbps = 0
            phase = .upload
            uploadMbps = try await Self.measure(upload: true) { [weak self] mbps in
                Task { @MainActor in self?.liveMbps = mbps }
            }

            liveMbps = 0
            phase = .done
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Measurements

    private nonisolated static let base = "https://speed.cloudflare.com"

    private nonisolated static func measureLatency() async throws -> (Double, Double) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel() }

        var samples: [Double] = []
        for i in 0..<9 {
            try Task.checkCancellation()
            var req = URLRequest(url: URL(string: "\(base)/__down?bytes=0&r=\(UUID().uuidString)")!)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try await session.data(for: req)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
            if i > 0 { samples.append(ms) }   // first request pays DNS + TLS, discard it
        }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let jitter = zip(samples, samples.dropFirst()).map { abs($0 - $1) }.reduce(0, +) / Double(samples.count - 1)
        return (median, jitter)
    }

    /// Multi-stream throughput. The first `warmup` seconds are excluded from the final number (TCP ramp-up).
    private nonisolated static func measure(upload: Bool,
                                duration: TimeInterval = 9,
                                warmup: TimeInterval = 2,
                                streams: Int = 6,
                                onLive: @escaping @Sendable (Double) -> Void) async throws -> Double {
        let transfer = Transfer()
        defer { transfer.stop() }

        if upload {
            let payload = Data(count: 4_000_000)
            transfer.makeTask = { session in
                var req = URLRequest(url: URL(string: "\(base)/__up?r=\(UUID().uuidString)")!)
                req.httpMethod = "POST"
                req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                return session.uploadTask(with: req, from: payload)
            }
        } else {
            transfer.makeTask = { session in
                var req = URLRequest(url: URL(string: "\(base)/__down?bytes=100000000&r=\(UUID().uuidString)")!)
                req.cachePolicy = .reloadIgnoringLocalCacheData
                return session.dataTask(with: req)
            }
        }
        transfer.start(streams: streams)

        let start = Date()
        var lastBytes: Int64 = 0
        var lastTime = start
        var ema = 0.0
        var warmBytes: Int64?
        var warmTime: Date?

        while true {
            try await Task.sleep(nanoseconds: 250_000_000)   // throws on cancel
            let now = Date()
            let bytes = transfer.counter.total

            let inst = Double(bytes - lastBytes) * 8 / max(now.timeIntervalSince(lastTime), 0.001) / 1e6
            ema = ema == 0 ? inst : ema * 0.6 + inst * 0.4
            onLive(ema)
            lastBytes = bytes
            lastTime = now

            let elapsed = now.timeIntervalSince(start)
            if warmBytes == nil, elapsed >= warmup { warmBytes = bytes; warmTime = now }
            if elapsed >= duration { break }
            if elapsed >= 4, bytes == 0 { throw SpeedTestError.noData }
        }

        guard let wb = warmBytes, let wt = warmTime else { throw SpeedTestError.noData }
        let span = Date().timeIntervalSince(wt)
        let delta = transfer.counter.total - wb
        guard delta > 0, span > 0 else { throw SpeedTestError.noData }
        return Double(delta) * 8 / span / 1e6
    }
}
