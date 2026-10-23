import SwiftUI
import UserNotifications

@main
struct PulseApp: App {
    @StateObject private var monitor = NetworkMonitor()
    @StateObject private var tester = SpeedTester()
    @StateObject private var watcher = ConnectionWatcher()

    init() {
        // Menu bar only; also covers `swift run`, where there's no Info.plist LSUIElement
        NSApplication.shared.setActivationPolicy(.accessory)

        // Troubleshooting: `open -a Pulse --args --notification-check` sends a test alert and logs the settings
        if CommandLine.arguments.contains("--notification-check") {
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                Notifier.shared.requestAuthorization()
                Notifier.shared.send(title: "Pulse test", body: "If you see this banner, notifications work.")
                let s = await UNUserNotificationCenter.current().notificationSettings()
                NSLog("PulseNotificationCheck auth=%d alertStyle=%d alert=%d", s.authorizationStatus.rawValue,
                      s.alertStyle.rawValue, s.alertSetting.rawValue)
            }
        }
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
