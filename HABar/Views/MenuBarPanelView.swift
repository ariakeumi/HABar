import AppKit
import SwiftUI

/// MenuBarExtra caches its window. Keep only this lightweight host while hidden.
struct MenuBarPanelView: View {
    @ObservedObject var store: HomeAssistantStore
    @State private var isVisible = false

    var body: some View {
        Group {
            if isVisible {
                MenuBarContentView(store: store)
            } else {
                Color.clear.frame(width: 382, height: 60)
            }
        }
        .background {
            WindowVisibilityObserver { visible in
                isVisible = visible
                store.setChartPanelVisible(visible)
            }
        }
    }
}

struct WindowVisibilityObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: VisibilityView, context: Context) {
        nsView.onChange = onChange
    }

    static func dismantleNSView(_ nsView: VisibilityView, coordinator: ()) {
        nsView.stopObserving()
    }

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var lastVisibility = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { return }
            let center = NotificationCenter.default
            for name in [NSWindow.didChangeOcclusionStateNotification,
                         NSWindow.didBecomeKeyNotification,
                         NSWindow.didResignKeyNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    // Defer state changes until AppKit/SwiftUI has finished updating the window.
                    Task { @MainActor [weak self] in self?.updateVisibility() }
                })
            }
            Task { @MainActor [weak self] in self?.updateVisibility() }
        }

        func stopObserving() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            reportVisibility(false)
        }

        private func updateVisibility() {
            reportVisibility(window?.isVisible == true)
        }

        private func reportVisibility(_ visible: Bool) {
            guard lastVisibility != visible else { return }
            lastVisibility = visible
            let callback = onChange
            Task { @MainActor in callback?(visible) }
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
