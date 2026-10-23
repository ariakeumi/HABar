import Combine
import Foundation
import ServiceManagement

@MainActor
final class HomeAssistantStore: ObservableObject {
    @Published private(set) var configuration: HAConfiguration
    @Published private(set) var availableSensors: [SensorDescriptor] = []
    @Published private(set) var historyByEntityID: [String: [SensorHistoryPoint]] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingHistory = false
    @Published private(set) var historyErrorMessage: String?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginRequiresApproval = false
    @Published var errorMessage: String?
    @Published var launchAtLoginError: String?
    @Published var draftBaseURL: String
    @Published var draftToken: String

    private let api: HomeAssistantAPI
    private var savedToken: String
    private var initialRefreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    private var historyRefreshTask: Task<Void, Never>?
    private var pendingRefreshAfterCurrent = false
    private var isChartPanelVisible = false
    private var historyGeneration = 0

    init(
        api: HomeAssistantAPI? = nil,
        configuration: HAConfiguration? = nil,
        token: String? = nil,
        automaticallyRefresh: Bool = true
    ) {
        self.api = api ?? HomeAssistantAPI()

        let configuration = configuration ?? HAConfiguration.load()
        let token = token ?? KeychainStore.loadToken()

        self.configuration = configuration
        self.savedToken = token
        self.draftBaseURL = configuration.baseURLString
        self.draftToken = token

        refreshLaunchAtLoginStatus()
        if automaticallyRefresh {
            startAutoRefresh()
            initialRefreshTask = Task { [weak self] in
                await self?.refresh()
            }
        }
    }

    deinit {
        initialRefreshTask?.cancel()
        autoRefreshTask?.cancel()
        historyRefreshTask?.cancel()
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
        cancelHistoryRefresh(clearHistory: true)
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
        if isRefreshing {
            pendingRefreshAfterCurrent = true
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            pendingRefreshAfterCurrent = false
            guard let baseURL = configuration.normalizedBaseURL, !savedToken.isEmpty else {
                availableSensors = []
                cancelHistoryRefresh(clearHistory: true)
                errorMessage = "请先在设置中填写 Home Assistant 地址和长期访问令牌。"
                return
            }

            do {
                let states = try await api.fetchStates(baseURL: baseURL, token: savedToken)
                let sensors = states
                    .compactMap(SensorDescriptor.init(entity:))
                    .sorted { lhs, rhs in
                        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    }

                if availableSensors != sensors {
                    availableSensors = sensors
                }
                lastRefresh = Date()
                errorMessage = nil

                scheduleHistoryRefresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        } while pendingRefreshAfterCurrent && !Task.isCancelled
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

        historyByEntityID = [:]
        scheduleHistoryRefresh()
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

        historyByEntityID = [:]
        scheduleHistoryRefresh()
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

    func setChartPanelVisible(_ visible: Bool) {
        guard isChartPanelVisible != visible else { return }
        isChartPanelVisible = visible
        if visible {
            scheduleHistoryRefresh()
        } else {
            cancelHistoryRefresh(clearHistory: true)
        }
    }

    private func refreshHistory(
        baseURL: URL,
        token: String,
        entityIDs: [String],
        range: HistoryRange,
        generation: Int
    ) async {
        defer {
            if historyGeneration == generation {
                isLoadingHistory = false
                historyRefreshTask = nil
            }
        }

        var newHistory: [String: [SensorHistoryPoint]] = [:]
        var historyFailed = false
        var firstHistoryError: String?

        for entityID in entityIDs {
            guard !Task.isCancelled else { return }

            do {
                let points = try await api.fetchHistory(
                    baseURL: baseURL,
                    token: token,
                    entityID: entityID,
                    range: range
                )
                guard !Task.isCancelled else { return }
                newHistory[entityID] = points
            } catch {
                guard !Task.isCancelled else { return }
                historyFailed = true
                if firstHistoryError == nil {
                    firstHistoryError = error.localizedDescription
                }
                newHistory[entityID] = []
            }
        }

        guard !Task.isCancelled, isChartPanelVisible, historyGeneration == generation else { return }
        historyByEntityID = newHistory

        if historyFailed {
            if let firstHistoryError, !firstHistoryError.isEmpty {
                historyErrorMessage = firstHistoryError
            } else {
                historyErrorMessage = "当前值已更新，但部分历史记录读取失败。"
            }
        } else {
            historyErrorMessage = nil
        }
    }

    private func scheduleHistoryRefresh() {
        cancelHistoryRefresh(clearHistory: false)
        guard isChartPanelVisible,
              let baseURL = configuration.normalizedBaseURL,
              !savedToken.isEmpty else { return }

        let entityIDs = configuration.chartEntityIDs.reduce(into: [String]()) { result, id in
            if !id.isEmpty, !result.contains(id) { result.append(id) }
        }
        guard !entityIDs.isEmpty else {
            historyByEntityID = [:]
            return
        }

        let generation = historyGeneration
        let range = configuration.historyRange
        let token = savedToken
        isLoadingHistory = true
        historyRefreshTask = Task { [weak self] in
            await self?.refreshHistory(
                baseURL: baseURL,
                token: token,
                entityIDs: entityIDs,
                range: range,
                generation: generation
            )
        }
    }

    private func cancelHistoryRefresh(clearHistory: Bool) {
        historyGeneration += 1
        historyRefreshTask?.cancel()
        historyRefreshTask = nil
        isLoadingHistory = false
        historyErrorMessage = nil
        if clearHistory { historyByEntityID = [:] }
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
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                guard let self else { return }
                await self.refresh()
            }
        }
    }
}
