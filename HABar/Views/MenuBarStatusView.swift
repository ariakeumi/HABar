import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var store: HomeAssistantStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: store.menuBarSymbol)
            Text(store.menuBarText)
                .monospacedDigit()
        }
    }
}
