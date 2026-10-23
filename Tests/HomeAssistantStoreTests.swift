import Foundation

@main
struct StoreTests {
    @MainActor
    static func main() async throws {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let configuration = HAConfiguration(
            baseURLString: "https://fixture.invalid",
            menuBarEntityIDs: ["sensor.temperature", "", ""],
            chartEntityIDs: ["sensor.temperature", "sensor.temperature", "", ""],
            historyRange: .last24Hours
        )
        let store = HomeAssistantStore(
            api: HomeAssistantAPI(session: session),
            configuration: configuration,
            token: "fixture-token",
            automaticallyRefresh: false
        )
        // Model setters persist only into this test executable's preferences domain.
        await store.refresh()
        precondition(store.availableSensors.count == 1)
        precondition(store.menuBarText == "23°C")
        precondition(FixtureURLProtocol.historyRequests.isEmpty, "Hidden panel fetched history")
        precondition(store.historyByEntityID.isEmpty)
        store.setHistoryRange(.last6Hours)
        try await Task.sleep(for: .milliseconds(50))
        precondition(FixtureURLProtocol.historyRequests.isEmpty, "Settings change fetched hidden history")

        store.setChartPanelVisible(true)
        try await waitUntil { !store.isLoadingHistory }
        precondition(store.historyByEntityID.count == 1, "Duplicate selections must share history")
        precondition(store.historyPoints(for: "sensor.temperature").count >= 2)
        let loadedRequestCount = FixtureURLProtocol.historyRequests.count
        store.setChartPanelVisible(true)
        try await Task.sleep(for: .milliseconds(50))
        precondition(FixtureURLProtocol.historyRequests.count == loadedRequestCount, "Repeated visibility started a duplicate request")
        store.setChartPanelVisible(false)
        precondition(store.historyByEntityID.isEmpty && !store.isLoadingHistory)
        await store.refresh()
        precondition(FixtureURLProtocol.historyRequests.count == loadedRequestCount, "Background refresh fetched history")

        FixtureURLProtocol.historyDelay = 0.3
        store.setChartPanelVisible(true)
        try await waitUntil { FixtureURLProtocol.historyRequests.count > loadedRequestCount }
        store.setChartPanelVisible(false)
        try await Task.sleep(for: .milliseconds(400))
        precondition(store.historyByEntityID.isEmpty, "Cancelled request repopulated hidden history")
        precondition(store.historyErrorMessage == nil && !store.isLoadingHistory)

        // Rapid range changes must only publish the newest request.
        store.setChartPanelVisible(true)
        store.setHistoryRange(.last24Hours)
        FixtureURLProtocol.historyDelay = 0
        store.setHistoryRange(.last6Hours)
        try await waitUntil { !store.isLoadingHistory }
        precondition(store.historyByEntityID.count == 1)
        precondition(store.configuration.historyRange == .last6Hours)
        store.setChartSensor("", at: 0)
        store.setChartSensor("", at: 1)
        precondition(store.historyByEntityID.isEmpty && !store.isLoadingHistory)
        store.setChartPanelVisible(false)
        print("PASS: current values; hidden refresh; shared history; open/close; cancellation; range changes; empty selection")
    }

    @MainActor
    static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Timed out")
    }
}
