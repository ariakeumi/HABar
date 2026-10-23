import AppKit
import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var store: HomeAssistantStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: store.menuBarSymbol)
            Text(store.menuBarText)
                .font(.system(size: NSFont.systemFontSize, weight: .regular))
                .monospacedDigit()
        }
        // Use the same 22-point canvas as CodexBar's single-line status item.
        .frame(height: 22)
    }
}
