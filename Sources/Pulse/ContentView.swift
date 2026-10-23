import SwiftUI
import ServiceManagement

struct ContentView: View {
    @EnvironmentObject var monitor: NetworkMonitor
    @EnvironmentObject var tester: SpeedTester
    @EnvironmentObject var watcher: ConnectionWatcher
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusRow
            liveSection
            Divider()
            speedTestSection
            Divider()
            alertsSection
            Divider()
            footer
        }
        .padding(18)
        .frame(width: 300)
        .onChange(of: tester.phase) { phase in
            watcher.paused = tester.isRunning
            if phase == .done { watcher.speedTestFinished(downloadMbps: tester.downloadMbps) }
        }
    }

    // MARK: Connection status

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(watcher.statusLabel).font(.caption.weight(.medium))
            if let ms = watcher.latencyMs, watcher.status != .offline {
                Text(String(format: "· %.0f ms", ms))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
        }
    }

    private var statusColor: Color {
        switch watcher.status {
        case .online: return .green
        case .slow: return .orange
        case .offline: return .red
        case .unknown: return .gray
        }
    }

    // MARK: Alerts

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Notify when network is slow or down", isOn: $watcher.notificationsEnabled)
                .toggleStyle(.checkbox)
                .font(.caption)
            if watcher.notificationsEnabled {
                Picker("Slow if latency over", selection: $watcher.slowLatencyMs) {
                    ForEach(ConnectionWatcher.latencyChoices, id: \.self) { Text("\(Int($0)) ms").tag($0) }
                }
                .font(.caption)
                Picker("Speed test alert below", selection: $watcher.slowSpeedMbps) {
                    ForEach(ConnectionWatcher.speedChoices, id: \.self) { Text("\(Int($0)) Mbps").tag($0) }
                }
                .font(.caption)
                Button("Send test notification") { watcher.sendTestNotification() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    // MARK: Live usage

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                rate(label: "Download", bps: monitor.downBps, tint: .accentColor)
                Spacer()
                rate(label: "Upload", bps: monitor.upBps, tint: .secondary)
            }
            Sparkline(down: monitor.downHistory, up: monitor.upHistory)
                .frame(height: 44)
        }
    }

    private func rate(label: String, bps: Double, tint: Color) -> some View {
        let p = NetworkMonitor.parts(bps, bits: monitor.useBits)
        return VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(p.value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(p.unit).font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(tint == .secondary ? Color.primary : tint)
        }
    }

    // MARK: Speed test

    @ViewBuilder
    private var speedTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch tester.phase {
            case .idle:
                Button { tester.start() } label: {
                    Text("Run speed test").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

            case .latency, .download, .upload:
                runningView

            case .done:
                resultsView
                Button { tester.start() } label: {
                    Text("Test again").frame(maxWidth: .infinity)
                }
                .controlSize(.large)

            case .failed(let message):
                Text(message).font(.callout).foregroundStyle(.secondary)
                Button { tester.start() } label: {
                    Text("Retry").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
    }

    private var runningView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(phaseLabel).font(.caption).foregroundStyle(.secondary)
            if tester.phase == .latency {
                ProgressView().controlSize(.small)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", tester.liveMbps))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("Mbps").font(.callout).foregroundStyle(.secondary)
                }
            }
            Button("Cancel") { tester.cancel() }
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    private var phaseLabel: String {
        switch tester.phase {
        case .latency: return "Measuring latency…"
        case .download: return "Testing download…"
        case .upload: return "Testing upload…"
        default: return ""
        }
    }

    private var resultsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(mbps(tester.downloadMbps))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("Mbps").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                stat("Upload", mbps(tester.uploadMbps), "Mbps")
                Spacer()
                stat("Latency", ms(tester.latencyMs), "ms")
                Spacer()
                stat("Jitter", ms(tester.jitterMs), "ms")
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 16, weight: .medium, design: .rounded)).monospacedDigit()
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func mbps(_ v: Double?) -> String {
        guard let v else { return "–" }
        return v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    private func ms(_ v: Double?) -> String {
        guard let v else { return "–" }
        return String(format: "%.0f", v)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Session  ↓ \(NetworkMonitor.formatBytes(monitor.sessionDown))  ↑ \(NetworkMonitor.formatBytes(monitor.sessionUp))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Toggle("Show in bits (Mbps)", isOn: $monitor.useBits)
                .toggleStyle(.checkbox)
                .font(.caption)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: launchAtLogin) { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .keyboardShortcut("q")
            }
        }
    }
}

/// Two-series area/line chart of the last 60 seconds. Shared scale so up vs down is honest.
struct Sparkline: View {
    let down: [Double]
    let up: [Double]

    var body: some View {
        GeometryReader { geo in
            let peak = max(down.max() ?? 0, up.max() ?? 0, 10_000)
            ZStack {
                area(down, peak: peak, size: geo.size)
                    .fill(Color.accentColor.opacity(0.15))
                line(down, peak: peak, size: geo.size)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                line(up, peak: peak, size: geo.size)
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            }
        }
    }

    private func points(_ v: [Double], peak: Double, size: CGSize) -> [CGPoint] {
        guard v.count > 1 else { return [] }
        let step = size.width / CGFloat(v.count - 1)
        return v.enumerated().map { i, y in
            CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(y / peak) * (size.height - 2) - 1)
        }
    }

    private func line(_ v: [Double], peak: Double, size: CGSize) -> Path {
        Path { p in
            let pts = points(v, peak: peak, size: size)
            guard let first = pts.first else { return }
            p.move(to: first)
            pts.dropFirst().forEach { p.addLine(to: $0) }
        }
    }

    private func area(_ v: [Double], peak: Double, size: CGSize) -> Path {
        Path { p in
            let pts = points(v, peak: peak, size: size)
            guard let first = pts.first, let last = pts.last else { return }
            p.move(to: CGPoint(x: first.x, y: size.height))
            pts.forEach { p.addLine(to: $0) }
            p.addLine(to: CGPoint(x: last.x, y: size.height))
            p.closeSubpath()
        }
    }
}
