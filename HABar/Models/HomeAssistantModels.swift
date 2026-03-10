import Foundation
import SwiftUI

struct HAEntityState: Decodable {
    let entityID: String
    let state: String
    let attributes: HAEntityAttributes
    let lastChanged: Date?

    enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case state
        case attributes
        case lastChanged = "last_changed"
    }
}

struct HAEntityAttributes: Decodable {
    let friendlyName: String?
    let unitOfMeasurement: String?
    let deviceClass: String?

    enum CodingKeys: String, CodingKey {
        case friendlyName = "friendly_name"
        case unitOfMeasurement = "unit_of_measurement"
        case deviceClass = "device_class"
    }
}

struct HAHistoryState: Decodable {
    let state: String
    let lastChanged: Date?
    let lastUpdated: Date?

    enum CodingKeys: String, CodingKey {
        case state
        case lastChanged = "last_changed"
        case lastUpdated = "last_updated"
    }

    var effectiveDate: Date? {
        lastChanged ?? lastUpdated
    }
}

struct SensorDescriptor: Identifiable, Hashable {
    let entityID: String
    let name: String
    let unit: String
    let deviceClass: String?
    let rawState: String

    var id: String { entityID }

    var numericValue: Double? {
        Double(rawState.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var formattedValue: String {
        if let numericValue {
            let number = SensorValueFormatter.format(numericValue)
            return unit.isEmpty ? number : "\(number)\(unit)"
        }

        return rawState
    }

    init(
        entityID: String,
        name: String,
        unit: String = "",
        deviceClass: String? = nil,
        rawState: String = "--"
    ) {
        self.entityID = entityID
        self.name = name
        self.unit = unit
        self.deviceClass = deviceClass
        self.rawState = rawState
    }

    init?(entity: HAEntityState) {
        guard entity.entityID.hasPrefix("sensor.") else {
            return nil
        }

        entityID = entity.entityID
        name = entity.attributes.friendlyName ?? entity.entityID
        unit = entity.attributes.unitOfMeasurement ?? ""
        deviceClass = entity.attributes.deviceClass
        rawState = entity.state
    }
}

struct SensorHistoryPoint: Identifiable, Hashable {
    let date: Date
    let value: Double

    var id: Date { date }
}

struct ConfiguredSensorSelection: Identifiable, Hashable {
    let slotIndex: Int
    let entityID: String
    let sensor: SensorDescriptor

    var id: Int { slotIndex }
}

enum ChartColorOption: String, CaseIterable, Identifiable {
    case blue
    case green
    case orange
    case red

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue:
            return "蓝色"
        case .green:
            return "绿色"
        case .orange:
            return "橙色"
        case .red:
            return "红色"
        }
    }

    static let defaultPalette: [ChartColorOption] = [.blue, .green, .orange, .red]

    var swiftUIColor: Color {
        switch self {
        case .blue:
            return .blue
        case .green:
            return .green
        case .orange:
            return .orange
        case .red:
            return .red
        }
    }
}

enum HistoryRange: Int, CaseIterable, Identifiable {
    case last6Hours = 6
    case last24Hours = 24
    case last7Days = 168

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .last6Hours:
            return "6小时"
        case .last24Hours:
            return "24小时"
        case .last7Days:
            return "7天"
        }
    }
}

struct HAConfiguration {
    static let menuBarSlotCount = 3
    static let chartSlotCount = 4

    var baseURLString: String = ""
    var menuBarEntityIDs: [String] = Array(repeating: "", count: menuBarSlotCount)
    var chartEntityIDs: [String] = Array(repeating: "", count: chartSlotCount)
    var chartColorIDs: [String] = ChartColorOption.defaultPalette.map(\.rawValue)
    var historyRange: HistoryRange = .last24Hours

    var normalizedBaseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return URL(string: normalized)
    }

    static func load(from defaults: UserDefaults = .standard) -> HAConfiguration {
        let legacyTemperature = defaults.string(forKey: Keys.temperatureEntityID) ?? ""
        let legacyHumidity = defaults.string(forKey: Keys.humidityEntityID) ?? ""

        let storedMenuBarIDs = normalizedIDs(
            defaults.stringArray(forKey: Keys.menuBarEntityIDs)
                ?? [legacyTemperature, legacyHumidity]
        )

        let storedChartIDs = normalizedIDs(
            defaults.stringArray(forKey: Keys.chartEntityIDs)
                ?? [legacyTemperature, legacyHumidity]
        )

        let storedChartColorIDs = normalizedColorIDs(
            defaults.stringArray(forKey: Keys.chartColorIDs)
        )

        let storedRange: HistoryRange
        if let rawRange = defaults.object(forKey: Keys.historyRange) as? Int {
            storedRange = HistoryRange(rawValue: rawRange) ?? .last24Hours
        } else {
            storedRange = .last24Hours
        }

        return HAConfiguration(
            baseURLString: defaults.string(forKey: Keys.baseURLString) ?? "",
            menuBarEntityIDs: storedMenuBarIDs,
            chartEntityIDs: storedChartIDs,
            chartColorIDs: storedChartColorIDs,
            historyRange: storedRange
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(baseURLString, forKey: Keys.baseURLString)
        defaults.set(HAConfiguration.normalizedIDs(menuBarEntityIDs), forKey: Keys.menuBarEntityIDs)
        defaults.set(HAConfiguration.normalizedIDs(chartEntityIDs), forKey: Keys.chartEntityIDs)
        defaults.set(HAConfiguration.normalizedColorIDs(chartColorIDs), forKey: Keys.chartColorIDs)
        defaults.set(historyRange.rawValue, forKey: Keys.historyRange)
    }

    private enum Keys {
        static let baseURLString = "ha.baseURLString"
        static let menuBarEntityIDs = "ha.menuBarEntityIDs"
        static let chartEntityIDs = "ha.chartEntityIDs"
        static let chartColorIDs = "ha.chartColorIDs"
        static let temperatureEntityID = "ha.temperatureEntityID"
        static let humidityEntityID = "ha.humidityEntityID"
        static let historyRange = "ha.historyRange"
    }

    private static func normalizedIDs(_ ids: [String]) -> [String] {
        let trimmed = ids
            .prefix(max(menuBarSlotCount, chartSlotCount))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return Array(trimmed)
    }

    private static func normalizedColorIDs(_ ids: [String]?) -> [String] {
        let provided = ids ?? []
        var normalized = Array(
            provided
                .prefix(chartSlotCount)
                .map { ChartColorOption(rawValue: $0)?.rawValue ?? ChartColorOption.defaultPalette[0].rawValue }
        )

        while normalized.count < chartSlotCount {
            normalized.append(ChartColorOption.defaultPalette[normalized.count].rawValue)
        }

        return normalized
    }

    init(
        baseURLString: String = "",
        menuBarEntityIDs: [String] = Array(repeating: "", count: menuBarSlotCount),
        chartEntityIDs: [String] = Array(repeating: "", count: chartSlotCount),
        chartColorIDs: [String] = ChartColorOption.defaultPalette.map(\.rawValue),
        historyRange: HistoryRange = .last24Hours
    ) {
        self.baseURLString = baseURLString
        self.menuBarEntityIDs = Array(
            HAConfiguration.normalizedIDs(menuBarEntityIDs)
                .prefix(HAConfiguration.menuBarSlotCount)
        )
        self.chartEntityIDs = Array(
            HAConfiguration.normalizedIDs(chartEntityIDs)
                .prefix(HAConfiguration.chartSlotCount)
        )
        self.chartColorIDs = Array(
            HAConfiguration.normalizedColorIDs(chartColorIDs)
                .prefix(HAConfiguration.chartSlotCount)
        )
        self.historyRange = historyRange

        if self.menuBarEntityIDs.count < HAConfiguration.menuBarSlotCount {
            self.menuBarEntityIDs += Array(
                repeating: "",
                count: HAConfiguration.menuBarSlotCount - self.menuBarEntityIDs.count
            )
        }

        if self.chartEntityIDs.count < HAConfiguration.chartSlotCount {
            self.chartEntityIDs += Array(
                repeating: "",
                count: HAConfiguration.chartSlotCount - self.chartEntityIDs.count
            )
        }

        if self.chartColorIDs.count < HAConfiguration.chartSlotCount {
            self.chartColorIDs += Array(
                ChartColorOption.defaultPalette
                    .dropFirst(self.chartColorIDs.count)
                    .prefix(HAConfiguration.chartSlotCount - self.chartColorIDs.count)
                    .map(\.rawValue)
            )
        }
    }
}

enum SensorValueFormatter {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.minimumIntegerDigits = 1
        return formatter
    }()

    static func format(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}

enum HADateParser {
    private static let historyFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackHistoryFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let requestFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ string: String) -> Date? {
        historyFormatter.date(from: string) ?? fallbackHistoryFormatter.date(from: string)
    }

    static func string(from date: Date) -> String {
        historyFormatter.string(from: date)
    }

    static func requestString(from date: Date) -> String {
        requestFormatter.string(from: date)
    }

    static func urlEncodedQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
