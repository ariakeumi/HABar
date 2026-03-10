//
//  HABarApp.swift
//  HABar
//
//  Created by 陈土豆 on 2026/3/10.
//

import SwiftUI

@main
struct HABarApp: App {
    @StateObject private var store = HomeAssistantStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: store)
        } label: {
            MenuBarStatusView(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}
