import Foundation

nonisolated final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests: [URLRequest] = []
    nonisolated(unsafe) static var historyDelay: TimeInterval = 0
    private var responseWork: DispatchWorkItem?

    static var historyRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests.filter { $0.url!.path.contains("/history/") }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        Self.lock.unlock()
        let isHistory = request.url!.path.contains("/history/")
        let payload = isHistory
            ? "[[{\"state\":\"22\",\"last_changed\":\"2020-01-01T00:00:00Z\"},{\"state\":\"23\",\"last_changed\":\"\(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60)))\"}]]"
            : "[{\"entity_id\":\"sensor.temperature\",\"state\":\"23\",\"attributes\":{\"friendly_name\":\"Temperature\",\"unit_of_measurement\":\"°C\"}}]"
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let response = HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data(payload.utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        responseWork = work
        DispatchQueue.global().asyncAfter(deadline: .now() + (isHistory ? Self.historyDelay : 0), execute: work)
    }

    override func stopLoading() { responseWork?.cancel() }
}

