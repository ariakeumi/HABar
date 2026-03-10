import Foundation

enum HomeAssistantAPIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case unauthorized
    case http(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Home Assistant 地址无效。"
        case .invalidResponse:
            return "Home Assistant 返回了无法识别的数据。"
        case .unauthorized:
            return "Home Assistant 认证失败，请检查长期访问令牌。"
        case let .http(statusCode, message):
            if let message, !message.isEmpty {
                return "Home Assistant 请求失败（\(statusCode)）：\(message)"
            }
            return "Home Assistant 请求失败（\(statusCode)）。"
        }
    }
}

struct HomeAssistantAPI {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let statisticsTypes = ["mean", "state", "sum", "max", "min"]

    init(session: URLSession = .shared) {
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)

            guard let date = HADateParser.parse(text) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid Home Assistant date: \(text)"
                )
            }

            return date
        }
        self.decoder = decoder
    }

    func fetchStates(baseURL: URL, token: String) async throws -> [HAEntityState] {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("states")

        let data = try await load(url: url, token: token)
        return try decoder.decode([HAEntityState].self, from: data)
    }

    func fetchHistory(
        baseURL: URL,
        token: String,
        entityID: String,
        range: HistoryRange
    ) async throws -> [SensorHistoryPoint] {
        let startDate = Date().addingTimeInterval(-Double(range.rawValue) * 3600)
        let endDate = Date()

        switch range {
        case .last6Hours, .last24Hours:
            return try await fetchStateHistory(
                baseURL: baseURL,
                token: token,
                entityID: entityID,
                range: range,
                startDate: startDate,
                endDate: endDate
            )
        case .last7Days:
            if let statisticsPoints = try await fetchStatisticsHistoryIfAvailable(
                baseURL: baseURL,
                token: token,
                entityID: entityID,
                range: range,
                startDate: startDate,
                endDate: endDate
            ) {
                return statisticsPoints
            }

            return try await fetchStateHistory(
                baseURL: baseURL,
                token: token,
                entityID: entityID,
                range: range,
                startDate: startDate,
                endDate: endDate
            )
        }
    }

    private func load(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HomeAssistantAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200 ..< 300:
            return data
        case 401:
            throw HomeAssistantAPIError.unauthorized
        default:
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw HomeAssistantAPIError.http(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func fetchStateHistory(
        baseURL: URL,
        token: String,
        entityID: String,
        range: HistoryRange,
        startDate: Date,
        endDate: Date
    ) async throws -> [SensorHistoryPoint] {
        let points = try await fetchRawHistoryPoints(
            baseURL: baseURL,
            token: token,
            entityID: entityID,
            startDate: startDate,
            endDate: endDate
        )

        let pointAtRangeStart = try await fetchPointAtRangeStart(
            from: points,
            baseURL: baseURL,
            token: token,
            entityID: entityID,
            range: range,
            startDate: startDate
        )

        guard !points.isEmpty || pointAtRangeStart != nil else {
            return []
        }

        return clippedHistoryPoints(
            from: points,
            pointAtRangeStart: pointAtRangeStart,
            startDate: startDate,
            endDate: endDate
        )
    }

    private func fetchStatisticsHistoryIfAvailable(
        baseURL: URL,
        token: String,
        entityID: String,
        range: HistoryRange,
        startDate: Date,
        endDate: Date
    ) async throws -> [SensorHistoryPoint]? {
        do {
            let points = try await fetchStatisticsHistory(
                baseURL: baseURL,
                token: token,
                entityID: entityID,
                range: range,
                startDate: startDate,
                endDate: endDate
            )

            return points.isEmpty ? nil : points
        } catch {
            return nil
        }
    }

    private func fetchStatisticsHistory(
        baseURL: URL,
        token: String,
        entityID: String,
        range: HistoryRange,
        startDate: Date,
        endDate: Date
    ) async throws -> [SensorHistoryPoint] {
        guard let websocketURL = websocketURL(baseURL: baseURL) else {
            throw HomeAssistantAPIError.invalidBaseURL
        }

        let websocketSession = URLSession(configuration: .ephemeral)
        let task = websocketSession.webSocketTask(with: websocketURL)
        task.resume()

        defer {
            task.cancel(with: .normalClosure, reason: nil)
            websocketSession.invalidateAndCancel()
        }

        let authRequired = try await receiveJSONObject(from: task)
        guard (authRequired["type"] as? String) == "auth_required" else {
            throw HomeAssistantAPIError.invalidResponse
        }

        try await sendJSONObject(
            [
                "type": "auth",
                "access_token": token,
            ],
            to: task
        )

        let authResponse = try await receiveJSONObject(from: task)
        switch authResponse["type"] as? String {
        case "auth_ok":
            break
        case "auth_invalid":
            throw HomeAssistantAPIError.unauthorized
        default:
            throw HomeAssistantAPIError.invalidResponse
        }

        try await sendJSONObject(
            statisticsCommand(
                id: 1,
                entityID: entityID,
                range: range,
                startDate: startDate,
                endDate: endDate
            ),
            to: task
        )

        while true {
            let message = try await receiveJSONObject(from: task)
            guard let type = message["type"] as? String else {
                continue
            }

            switch type {
            case "event":
                continue
            case "result":
                guard (message["id"] as? Int) == 1 else {
                    continue
                }

                guard (message["success"] as? Bool) == true else {
                    throw HomeAssistantAPIError.invalidResponse
                }

                return statisticsPoints(
                    from: message["result"],
                    entityID: entityID,
                    startDate: startDate,
                    endDate: endDate
                )
            default:
                continue
            }
        }
    }

    private func fetchRawHistoryPoints(
        baseURL: URL,
        token: String,
        entityID: String,
        startDate: Date,
        endDate: Date
    ) async throws -> [SensorHistoryPoint] {
        guard let url = historyURL(
            baseURL: baseURL,
            entityID: entityID,
            startDate: startDate,
            endDate: endDate
        ) else {
            throw HomeAssistantAPIError.invalidBaseURL
        }

        let data = try await load(url: url, token: token)
        let response = try decoder.decode([[HAHistoryState]].self, from: data)

        return response
            .flatMap { $0 }
            .compactMap { state -> SensorHistoryPoint? in
                guard
                    let date = state.effectiveDate,
                    let value = Double(state.state.trimmingCharacters(in: .whitespacesAndNewlines))
                else {
                    return nil
                }

                return SensorHistoryPoint(date: date, value: value)
            }
            .sorted { $0.date < $1.date }
    }

    private func websocketURL(baseURL: URL) -> URL? {
        guard var components = URLComponents(
            url: baseURL
                .appendingPathComponent("api")
                .appendingPathComponent("websocket"),
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }

        switch components.scheme?.lowercased() {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        case "ws", "wss":
            break
        default:
            return nil
        }

        return components.url
    }

    private func statisticsCommand(
        id: Int,
        entityID: String,
        range: HistoryRange,
        startDate: Date,
        endDate: Date
    ) -> [String: Any] {
        [
            "id": id,
            "type": "recorder/statistics_during_period",
            "start_time": HADateParser.requestString(from: startDate),
            "end_time": HADateParser.requestString(from: endDate),
            "statistic_ids": [entityID],
            "period": statisticsPeriod(for: range),
            "types": statisticsTypes,
        ]
    }

    private func statisticsPeriod(for range: HistoryRange) -> String {
        switch range {
        case .last6Hours, .last24Hours, .last7Days:
            return "hour"
        }
    }

    private func sendJSONObject(
        _ object: [String: Any],
        to task: URLSessionWebSocketTask
    ) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try await task.send(.data(data))
    }

    private func receiveJSONObject(
        from task: URLSessionWebSocketTask
    ) async throws -> [String: Any] {
        let message = try await task.receive()
        let data: Data

        switch message {
        case let .data(messageData):
            data = messageData
        case let .string(text):
            guard let messageData = text.data(using: .utf8) else {
                throw HomeAssistantAPIError.invalidResponse
            }
            data = messageData
        @unknown default:
            throw HomeAssistantAPIError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HomeAssistantAPIError.invalidResponse
        }

        return json
    }

    private func statisticsPoints(
        from payload: Any?,
        entityID: String,
        startDate: Date,
        endDate: Date
    ) -> [SensorHistoryPoint] {
        guard
            let result = payload as? [String: Any],
            let samples = result[entityID] as? [[String: Any]]
        else {
            return []
        }

        var points = samples
            .compactMap { sample -> SensorHistoryPoint? in
                guard
                    let date = statisticsDate(from: sample),
                    let value = statisticsValue(from: sample)
                else {
                    return nil
                }

                return SensorHistoryPoint(date: date, value: value)
            }
            .filter { $0.date >= startDate && $0.date <= endDate }
            .sorted { $0.date < $1.date }

        if points.count == 1, let point = points.first, point.date < endDate {
            points.append(SensorHistoryPoint(date: endDate, value: point.value))
        }

        return points
    }

    private func statisticsDate(from sample: [String: Any]) -> Date? {
        dateValue(from: sample["end"]) ?? dateValue(from: sample["start"])
    }

    private func statisticsValue(from sample: [String: Any]) -> Double? {
        numericValue(from: sample["mean"])
            ?? numericValue(from: sample["state"])
            ?? numericValue(from: sample["sum"])
            ?? numericValue(from: sample["max"])
            ?? numericValue(from: sample["min"])
    }

    private func numericValue(from rawValue: Any?) -> Double? {
        switch rawValue {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private func dateValue(from rawValue: Any?) -> Date? {
        switch rawValue {
        case let number as NSNumber:
            return Date(timeIntervalSince1970: number.doubleValue / 1000)
        case let string as String:
            if let milliseconds = Double(string) {
                return Date(timeIntervalSince1970: milliseconds / 1000)
            }
            return HADateParser.parse(string)
        default:
            return nil
        }
    }

    private func historyURL(
        baseURL: URL,
        entityID: String,
        startDate: Date,
        endDate: Date
    ) -> URL? {
        let startTime = HADateParser.requestString(from: startDate)
        let endTime = HADateParser.requestString(from: endDate)

        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("api")
                .appendingPathComponent("history")
                .appendingPathComponent("period")
                .appendingPathComponent(startTime),
            resolvingAgainstBaseURL: false
        )

        let encodedEntityID = HADateParser.urlEncodedQueryValue(entityID)
        let encodedEndTime = HADateParser.urlEncodedQueryValue(endTime)
        components?.percentEncodedQuery = [
            "filter_entity_id=\(encodedEntityID)",
            "end_time=\(encodedEndTime)",
            "minimal_response",
            "no_attributes"
        ].joined(separator: "&")

        return components?.url
    }

    private func fetchPointAtRangeStart(
        from points: [SensorHistoryPoint],
        baseURL: URL,
        token: String,
        entityID: String,
        range: HistoryRange,
        startDate: Date
    ) async throws -> SensorHistoryPoint? {
        if let pointAtRangeStart = points.last(where: { $0.date <= startDate }) {
            return pointAtRangeStart
        }

        let lookbackStart = startDate.addingTimeInterval(-Double(range.rawValue) * 3600)
        guard lookbackStart < startDate else {
            return nil
        }

        let lookbackPoints = try await fetchRawHistoryPoints(
            baseURL: baseURL,
            token: token,
            entityID: entityID,
            startDate: lookbackStart,
            endDate: startDate
        )

        return lookbackPoints.last(where: { $0.date <= startDate })
    }

    private func clippedHistoryPoints(
        from points: [SensorHistoryPoint],
        pointAtRangeStart: SensorHistoryPoint?,
        startDate: Date,
        endDate: Date
    ) -> [SensorHistoryPoint] {
        var clippedPoints: [SensorHistoryPoint] = []

        if let pointAtRangeStart {
            clippedPoints.append(
                SensorHistoryPoint(date: startDate, value: pointAtRangeStart.value)
            )
        }

        let pointsWithinRange = points.filter { $0.date > startDate && $0.date <= endDate }
        for point in pointsWithinRange {
            append(point, to: &clippedPoints)
        }

        if clippedPoints.isEmpty, let firstPointInRange = points.first(where: { $0.date >= startDate && $0.date <= endDate }) {
            clippedPoints.append(firstPointInRange)
        }

        if let lastPoint = clippedPoints.last, lastPoint.date < endDate {
            clippedPoints.append(
                SensorHistoryPoint(date: endDate, value: lastPoint.value)
            )
        }

        return clippedPoints
    }

    private func append(_ point: SensorHistoryPoint, to points: inout [SensorHistoryPoint]) {
        guard let lastPoint = points.last else {
            points.append(point)
            return
        }

        guard lastPoint.date != point.date || lastPoint.value != point.value else {
            return
        }

        points.append(point)
    }
}
