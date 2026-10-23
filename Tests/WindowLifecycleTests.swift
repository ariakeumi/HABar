import AppKit
import SwiftUI

/// Exercises real AppKit visibility notifications, including a retained, hidden host.
@main
struct WindowLifecycleTests {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = WindowTestDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class WindowTestDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await runTests() }
    }

    private func runTests() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let store = HomeAssistantStore(
            api: HomeAssistantAPI(session: session),
            configuration: HAConfiguration(
                baseURLString: "https://fixture.invalid",
                chartEntityIDs: ["sensor.temperature", "", "", ""],
                historyRange: .last6Hours
            ),
            token: "fixture-token",
            automaticallyRefresh: false
        )
        await store.refresh()
        let panel = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 382, height: 400),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.title = "HABar window lifecycle test"
        panel.contentView = NSHostingView(rootView: MenuBarPanelView(store: store))
        window = panel
        await settle()
        precondition(FixtureURLProtocol.historyRequests.isEmpty)

        for _ in 0..<3 {
            panel.orderFrontRegardless()
            await settle()
            precondition(!store.historyByEntityID.isEmpty, "Opening the window did not load charts")
            panel.orderOut(nil)
            await settle()
            precondition(store.historyByEntityID.isEmpty, "Hiding the cached window retained history")
            precondition(!store.isLoadingHistory)
            let requestCount = FixtureURLProtocol.historyRequests.count
            await store.refresh()
            await settle()
            precondition(FixtureURLProtocol.historyRequests.count == requestCount)
        }
        panel.orderFrontRegardless()
        await settle()
        precondition(!store.historyByEntityID.isEmpty)
        panel.close()
        await settle()
        precondition(store.historyByEntityID.isEmpty && !store.isLoadingHistory)
        print("PASS: real window visibility; retained host; repeated open/close; hidden refresh")
        NSApplication.shared.terminate(nil)
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(500))
    }
}
