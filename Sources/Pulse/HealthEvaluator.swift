import Foundation

enum NetStatus: Equatable {
    case unknown, online, slow, offline
}

/// Turns a stream of probe results into a debounced status, so one bad ping doesn't fire a notification.
/// Kept free of networking so it can be unit tested.
struct HealthEvaluator {
    var slowLatencyMs: Double
    var failuresForOffline = 2
    var slowSamplesNeeded = 3
    var goodSamplesForRecovery = 2

    private(set) var status: NetStatus = .unknown
    private var failures = 0
    private var slow = 0
    private var good = 0

    init(slowLatencyMs: Double) {
        self.slowLatencyMs = slowLatencyMs
    }

    /// Feed one probe. `latencyMs == nil` means the probe failed.
    /// Returns the new status only when it changed.
    mutating func record(latencyMs: Double?, pathUp: Bool) -> NetStatus? {
        let next = evaluate(latencyMs: latencyMs, pathUp: pathUp)
        guard next != status else { return nil }
        status = next
        return next
    }

    private mutating func evaluate(latencyMs: Double?, pathUp: Bool) -> NetStatus {
        guard pathUp else {
            failures = 0; slow = 0; good = 0
            return .offline
        }
        guard let ms = latencyMs else {
            failures += 1
            good = 0
            return failures >= failuresForOffline ? .offline : status
        }
        failures = 0
        if ms > slowLatencyMs {
            slow += 1; good = 0
        } else {
            good += 1; slow = 0
        }
        if slow >= slowSamplesNeeded { return .slow }

        switch status {
        case .unknown:
            return good > 0 ? .online : .unknown
        case .online:
            return .online
        case .slow, .offline:
            return good >= goodSamplesForRecovery ? .online : status
        }
    }

    /// What to tell the user when moving from `old` to `new`, or nil for silent transitions.
    static func message(from old: NetStatus, to new: NetStatus, latencyMs: Double?) -> (title: String, body: String)? {
        switch (old, new) {
        case (_, .offline):
            return ("Network down", "Your Mac lost its internet connection.")
        case (_, .slow):
            let ms = latencyMs.map { String(format: "%.0f ms", $0) } ?? "high"
            return ("Network is slow", "Latency is \(ms). Pages and calls may lag.")
        case (.offline, .online):
            return ("Back online", "Your internet connection is restored.")
        case (.slow, .online):
            return ("Network back to normal", "Latency has recovered.")
        default:
            return nil
        }
    }
}
