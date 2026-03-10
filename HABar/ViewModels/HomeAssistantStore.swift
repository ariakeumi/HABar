import Combine
import Foundation
import ServiceManagement

@MainActor
final class HomeAssistantStore: ObservableObject {
    @Published private(set) var configuration: HAConfiguration
    @Published private(set) var availableSensors: [SensorDescriptor] = []
    @Published private(set) var historyByEntityID: [String: [SensorHistoryPoint]] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginRequiresApproval = false
    @Published var errorMessage: String?
    @Published var launchAtLoginError: String?
    @Published var draftBaseURL: String
    @Published var draftToken: String

    private let api: HomeAssistantAPI
    private var savedToken: String
    private var autoRefreshTask: Task<Void, Never>?

    init(api: HomeAssistantAPI? = nil) {
        self.api = api ?? HomeAssistantAPI()

        let configuration = HAConfiguration.load()
        let token = KeychainStore.loadToken()

        self.configuration = configuration
        self.savedToken = token
        self.draftBaseURL = configuration.baseURLString
        self.draftToken = token

        refreshLaunchAtLoginStatus()
        startAutoRefresh()

        Task {
            await refresh()
        }
    }

    deinit {
        autoRefreshTask?.cancel()
    }

    var menuBarText: String {
        let values = menuBarSelections
            .compactMap { menuBarValue(for: $0.entityID) }

        if !values.isEmpty {
            return values.joined(separator: " ")
        }

        if isConfigured {
            return "HA --"
        }

        return "HABar"
    }

    var menuBarSymbol: String {
        if errorMessage != nil {
            return "exclamationmark.triangle.fill"
        }

        if isConfigured {
            return "house"
        }

        return "house.badge.plus"
    }

    var isConfigured: Bool {
        configuration.normalizedBaseURL != nil && !savedToken.isEmpty
    }

    var sensorCountText: String {
        "已发现 \(availableSensors.count) 个传感器实体"
    }

    var launchAtLoginSelection: Bool {
        launchAtLoginEnabled || launchAtLoginRequiresApproval
    }

    var chartSelectionCount: Int {
        chartSelections.count
    }

    var menuBarSelections: [ConfiguredSensorSelection] {
        configuration.menuBarEntityIDs.enumerated().compactMap { index, entityID in
            configuredSelection(entityID: entityID, slotIndex: index)
        }
    }

    var chartSelections: [ConfiguredSensorSelection] {
        configuration.chartEntityIDs.enumerated().compactMap { index, entityID in
            configuredSelection(entityID: entityID, slotIndex: index)
        }
    }

    func saveConnectionSettings() async {
        objectWillChange.send()
        configuration.baseURLString = draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.save()

        savedToken = draftToken.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try KeychainStore.saveToken(savedToken)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        await refresh()
    }

    func refresh() async {
        guard let baseURL = configuration.normalizedBaseURL, !savedToken.isEmpty else {
            availableSensors = []
            historyByEntityID = [:]
            errorMessage = "请先在设置中填写 Home Assistant 地址和长期访问令牌。"
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let states = try await api.fetchStates(baseURL: baseURL, token: savedToken)
            let sensors = states
                .compactMap(SensorDescriptor.init(entity:))
                .sorted { lhs, rhs in
                    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }

            availableSensors = sensors
            lastRefresh = Date()
            errorMessage = nil

            await refreshHistory(baseURL: baseURL, token: savedToken)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setMenuBarSensor(_ entityID: String, at index: Int) {
        guard configuration.menuBarEntityIDs.indices.contains(index) else {
            return
        }

        objectWillChange.send()
        configuration.menuBarEntityIDs[index] = entityID.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.save()
    }

    func setChartSensor(_ entityID: String, at index: Int) {
        guard configuration.chartEntityIDs.indices.contains(index) else {
            return
        }

        objectWillChange.send()
        configuration.chartEntityIDs[index] = entityID.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.save()

        Task {
            await refreshHistoryOnly()
        }
    }

    func chartColor(at index: Int) -> ChartColorOption {
        guard configuration.chartColorIDs.indices.contains(index) else {
            return ChartColorOption.defaultPalette[0]
        }

        return ChartColorOption(rawValue: configuration.chartColorIDs[index])
            ?? ChartColorOption.defaultPalette[min(index, ChartColorOption.defaultPalette.count - 1)]
    }

    func setChartColor(_ color: ChartColorOption, at index: Int) {
        guard configuration.chartColorIDs.indices.contains(index) else {
            return
        }

        objectWillChange.send()
        configuration.chartColorIDs[index] = color.rawValue
        configuration.save()
    }

    func setHistoryRange(_ range: HistoryRange) {
        guard configuration.historyRange != range else {
            return
        }

        objectWillChange.send()
        configuration.historyRange = range
        configuration.save()

        Task {
            await refreshHistoryOnly()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }

        refreshLaunchAtLoginStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func sensorCandidates() -> [SensorDescriptor] {
        availableSensors
    }

    private func refreshHistoryOnly() async {
        guard let baseURL = configuration.normalizedBaseURL, !savedToken.isEmpty else {
            historyByEntityID = [:]
            return
        }

        await refreshHistory(baseURL: baseURL, token: savedToken)
    }

    private func refreshHistory(baseURL: URL, token: String) async {
        let entityIDs = Array(NSOrderedSet(array: configuration.chartEntityIDs.filter { !$0.isEmpty })) as? [String] ?? []

        guard !entityIDs.isEmpty else {
            historyByEntityID = [:]
            return
        }

        var newHistory: [String: [SensorHistoryPoint]] = [:]
        var historyFailed = false
        var firstHistoryError: String?

        for entityID in entityIDs {
            do {
                newHistory[entityID] = try await api.fetchHistory(
                    baseURL: baseURL,
                    token: token,
                    entityID: entityID,
                    range: configuration.historyRange
                )
            } catch {
                historyFailed = true
                if firstHistoryError == nil {
                    firstHistoryError = error.localizedDescription
                }
                newHistory[entityID] = []
            }
        }

        historyByEntityID = newHistory

        if historyFailed {
            if let firstHistoryError, !firstHistoryError.isEmpty {
                errorMessage = firstHistoryError
            } else {
                errorMessage = "当前值已更新，但部分历史记录读取失败。"
            }
        } else {
            errorMessage = nil
        }
    }

    func menuBarSelection(at index: Int) -> String {
        guard configuration.menuBarEntityIDs.indices.contains(index) else {
            return ""
        }

        return configuration.menuBarEntityIDs[index]
    }

    func chartSelection(at index: Int) -> String {
        guard configuration.chartEntityIDs.indices.contains(index) else {
            return ""
        }

        return configuration.chartEntityIDs[index]
    }

    func menuBarValue(for entityID: String) -> String? {
        guard !entityID.isEmpty else {
            return nil
        }

        if let sensor = availableSensors.first(where: { $0.entityID == entityID }) {
            return sensor.formattedValue
        }

        return "--"
    }

    func historyPoints(for entityID: String) -> [SensorHistoryPoint] {
        guard !entityID.isEmpty else {
            return []
        }

        return historyByEntityID[entityID] ?? []
    }

    private func configuredSelection(entityID: String, slotIndex: Int) -> ConfiguredSensorSelection? {
        let trimmedID = entityID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            return nil
        }

        if let sensor = availableSensors.first(where: { $0.entityID == trimmedID }) {
            return ConfiguredSensorSelection(slotIndex: slotIndex, entityID: trimmedID, sensor: sensor)
        }

        let fallbackSensor = SensorDescriptor(
            entityID: trimmedID,
            name: trimmedID,
            rawState: "无当前值"
        )
        return ConfiguredSensorSelection(slotIndex: slotIndex, entityID: trimmedID, sensor: fallbackSensor)
    }

    private func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled
        launchAtLoginRequiresApproval = status == .requiresApproval
    }

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                await self.refresh()
            }
        }
    }
}
