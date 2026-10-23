import Foundation
import Darwin

/// Polls interface byte counters once a second and publishes live throughput.
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var downBps: Double = 0   // bytes per second
    @Published private(set) var upBps: Double = 0
    @Published private(set) var downHistory: [Double] = Array(repeating: 0, count: 60)
    @Published private(set) var upHistory: [Double] = Array(repeating: 0, count: 60)
    @Published private(set) var sessionDown: UInt64 = 0
    @Published private(set) var sessionUp: UInt64 = 0

    @Published var useBits: Bool {
        didSet { UserDefaults.standard.set(useBits, forKey: "useBits") }
    }

    private var last: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var lastTime: Date?
    private var timer: Timer?

    init() {
        useBits = UserDefaults.standard.bool(forKey: "useBits")
        last = Self.readCounters()
        lastTime = Date()

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // .common so it keeps firing while the menu window is open
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }

    var menuText: String {
        "↓ \(Self.format(downBps, bits: useBits))  ↑ \(Self.format(upBps, bits: useBits))"
    }

    private func tick() {
        let now = Date()
        let current = Self.readCounters()
        let dt = max(now.timeIntervalSince(lastTime ?? now), 0.001)

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        for (name, cur) in current {
            guard let prev = last[name] else { continue }
            // getifaddrs counters are 32-bit and wrap; wrapping subtraction handles it
            rx += UInt64(cur.rx &- prev.rx)
            tx += UInt64(cur.tx &- prev.tx)
        }
        last = current
        lastTime = now

        var down = Double(rx) / dt
        var up = Double(tx) / dt
        // An interface reset can look like a huge spurious delta; drop anything past 100 Gbps
        if down > 12.5e9 { down = 0 }
        if up > 12.5e9 { up = 0 }

        downBps = down
        upBps = up
        sessionDown += UInt64(down * dt)
        sessionUp += UInt64(up * dt)
        downHistory.append(down); downHistory.removeFirst()
        upHistory.append(up); upHistory.removeFirst()
    }

    // MARK: - Counters

    /// Physical interfaces only (en*, cellular). Skips lo0 and tunnels so VPN traffic isn't double counted.
    private static func readCounters() -> [String: (rx: UInt32, tx: UInt32)] {
        var result: [String: (rx: UInt32, tx: UInt32)] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return result }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cursor {
            let ifa = p.pointee
            if let addr = ifa.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               let data = ifa.ifa_data {
                let name = String(cString: ifa.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("pdp_ip") {
                    let d = data.assumingMemoryBound(to: if_data.self).pointee
                    result[name] = (d.ifi_ibytes, d.ifi_obytes)
                }
            }
            cursor = ifa.ifa_next
        }
        return result
    }

    // MARK: - Formatting

    static func parts(_ bytesPerSec: Double, bits: Bool) -> (value: String, unit: String) {
        if bits {
            let b = bytesPerSec * 8
            switch b {
            case 1e9...: return (String(format: "%.2f", b / 1e9), "Gbps")
            case 1e6...: return (String(format: "%.1f", b / 1e6), "Mbps")
            case 1e3...: return (String(format: "%.0f", b / 1e3), "Kbps")
            default:     return (String(format: "%.0f", b), "bps")
            }
        } else {
            switch bytesPerSec {
            case 1e9...: return (String(format: "%.2f", bytesPerSec / 1e9), "GB/s")
            case 1e6...: return (String(format: "%.1f", bytesPerSec / 1e6), "MB/s")
            case 1e3...: return (String(format: "%.0f", bytesPerSec / 1e3), "KB/s")
            default:     return (String(format: "%.0f", bytesPerSec), "B/s")
            }
        }
    }

    static func format(_ bytesPerSec: Double, bits: Bool) -> String {
        let p = parts(bytesPerSec, bits: bits)
        return "\(p.value) \(p.unit)"
    }

    static func formatBytes(_ n: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .decimal)
    }
}
