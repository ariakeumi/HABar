import SwiftUI

/// SwiftUI retains the settings window after closing; release its form while hidden.
struct SettingsWindowView: View {
    @ObservedObject var store: HomeAssistantStore
    @State private var isVisible = false

    var body: some View {
        Group {
            if isVisible {
                SettingsView(store: store)
            } else {
                Color.clear.frame(width: 660, height: 600)
            }
        }
        .background {
            WindowVisibilityObserver { isVisible = $0 }
        }
    }
}
