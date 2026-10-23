import SwiftUI

@main
struct PulseApp: App {
    @StateObject private var monitor = NetworkMonitor()
    @StateObject private var tester = SpeedTester()

    init() {
        // Menu bar only; also covers `swift run`, where there's no Info.plist LSUIElement
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(tester)
        } label: {
            Text(monitor.menuText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .menuBarExtraStyle(.window)
    }
}
