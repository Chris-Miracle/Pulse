import Foundation
import Network
import UserNotifications

/// Watches connectivity and latency in the background and sends notifications when the network goes down,
/// gets slow, or recovers.
@MainActor
final class ConnectionWatcher: ObservableObject {
    @Published private(set) var status: NetStatus = .unknown
    @Published private(set) var latencyMs: Double?

    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
            if notificationsEnabled { Notifier.shared.requestAuthorization() }
        }
    }
    @Published var slowLatencyMs: Double {
        didSet {
            UserDefaults.standard.set(slowLatencyMs, forKey: "slowLatencyMs")
            evaluator.slowLatencyMs = slowLatencyMs
        }
    }
    @Published var slowSpeedMbps: Double {
        didSet { UserDefaults.standard.set(slowSpeedMbps, forKey: "slowSpeedMbps") }
    }

    /// Set while a speed test runs: a saturated link inflates latency and would cause false "slow" alerts.
    var paused = false

    static let latencyChoices: [Double] = [150, 250, 500, 1000]
    static let speedChoices: [Double] = [5, 10, 25, 50]

    private var evaluator: HealthEvaluator
    private let pathMonitor = NWPathMonitor()
    private var pathUp = true
    private var pathDownCheck: Task<Void, Never>?
    private var timer: Timer?
    private var probing = false
    private let interval: TimeInterval = 15

    // Reused so we measure round trips, not a fresh DNS + TLS handshake every time
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 5
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["notificationsEnabled": true, "slowLatencyMs": 250.0, "slowSpeedMbps": 10.0])
        notificationsEnabled = d.bool(forKey: "notificationsEnabled")
        slowLatencyMs = d.double(forKey: "slowLatencyMs")
        slowSpeedMbps = d.double(forKey: "slowSpeedMbps")
        evaluator = HealthEvaluator(slowLatencyMs: d.double(forKey: "slowLatencyMs"))

        if notificationsEnabled { Notifier.shared.requestAuthorization() }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in self?.pathChanged(up: up) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "pulse.path"))

        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.probe() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Task { await probe() }
    }

    deinit {
        timer?.invalidate()
        pathMonitor.cancel()
    }

    var statusLabel: String {
        switch status {
        case .unknown: return "Checking…"
        case .online: return "Online"
        case .slow: return "Slow"
        case .offline: return "Offline"
        }
    }

    /// Called when a manual speed test finishes.
    func speedTestFinished(downloadMbps: Double?) {
        guard let down = downloadMbps, down < slowSpeedMbps else { return }
        notify("Slow download speed",
               String(format: "Speed test measured %.1f Mbps (below your %.0f Mbps alert).", down, slowSpeedMbps))
    }

    func sendTestNotification() {
        Notifier.shared.send(title: "Pulse notifications are on",
                             body: "You'll be alerted when your network is slow or down.")
    }

    // MARK: - Internals

    private func pathChanged(up: Bool) {
        pathUp = up
        pathDownCheck?.cancel()
        if up {
            Task { await probe() }
        } else {
            // Wait a few seconds so Wi-Fi roaming or a network switch doesn't count as an outage
            pathDownCheck = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self, !self.pathUp else { return }
                self.apply(latency: nil)
            }
        }
    }

    private func probe() async {
        guard !paused, !probing, pathUp else { return }
        probing = true
        defer { probing = false }
        let ms = await measure()
        guard !paused else { return }
        apply(latency: ms)
    }

    private func apply(latency ms: Double?) {
        latencyMs = ms
        let old = evaluator.status
        guard let new = evaluator.record(latencyMs: ms, pathUp: pathUp) else { return }
        status = new
        if let msg = HealthEvaluator.message(from: old, to: new, latencyMs: ms) {
            notify(msg.title, msg.body)
        }
    }

    private func notify(_ title: String, _ body: String) {
        guard notificationsEnabled else { return }
        Notifier.shared.send(title: title, body: body)
    }

    /// Round trip to Cloudflare; falls back to Apple's captive portal check so one provider's outage isn't "offline".
    private func measure() async -> Double? {
        let urls = [
            "https://speed.cloudflare.com/__down?bytes=0",
            "https://captive.apple.com/hotspot-detect.html",
        ]
        for u in urls {
            guard let url = URL(string: u) else { continue }
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let t0 = DispatchTime.now().uptimeNanoseconds
            do {
                let (_, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { continue }
                return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
            } catch {
                continue
            }
        }
        return nil
    }
}

/// Thin wrapper over UNUserNotificationCenter. It needs a real .app bundle, so it's a no-op under `swift run`.
final class Notifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = Notifier()

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func requestAuthorization() {
        guard let center else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func send(title: String, body: String) {
        guard let center else {
            print("[notification] \(title): \(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Same identifier replaces the previous alert instead of stacking a pile of them
        let req = UNNotificationRequest(identifier: "pulse.status", content: content, trigger: nil)
        center.add(req)
    }

    // Show banners even while the menu bar popover is open
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
