import SwiftUI

@main
struct PulseApp: App {
    @StateObject private var monitor = NetworkMonitor()
    @StateObject private var tester = SpeedTester()
    @StateObject private var watcher = ConnectionWatcher()

    init() {
        // Menu bar only; also covers `swift run`, where there's no Info.plist LSUIElement
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(tester)
                .environmentObject(watcher)
        } label: {
            Text(menuLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .menuBarExtraStyle(.window)
    }

    private var menuLabel: String {
        switch watcher.status {
        case .offline: return "⚠︎ Offline"
        case .slow: return "⚠︎ " + monitor.menuText
        default: return monitor.menuText
        }
    }
}
