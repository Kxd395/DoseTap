import Foundation

// MARK: - Transport Protocol
public protocol APITransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
public struct URLSessionTransport: APITransport {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, http)
    }
}

// Note: APIError is now defined in APIErrors.swift

// MARK: - Response Models
public struct EventResponse: Codable {
    public let eventId: String
    public let event: String
    public let at: String
    
    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case event, at
    }
}

// MARK: - Client
@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
public final class APIClient {
    /// Medication mutation endpoints are intentionally absent. Dose 1, Dose 2,
    /// skip, and snooze must stay local and route through DoseActionCoordinator.
    public enum Endpoint: String, CaseIterable { 
        case logEvent = "/events/log"
        case exportAnalytics = "/analytics/export"
    }
    
    private let baseURL: URL
    private let transport: APITransport
    public var token: String?

    public init(baseURL: URL, transport: APITransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.transport = transport
    }
    
    private func makeRequest(path: String, method: String = "POST", body: Encodable? = nil) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        return req
    }
    
    // MARK: - Private Request Bodies
    private struct LogEventBody: Encodable { let event: String; let at: String }
    
    @discardableResult
    public func logEvent(_ name: String, at date: Date = Date()) async throws -> EventResponse {
        let body = LogEventBody(event: name, at: ISO8601DateFormatter().string(from: date))
        let req = try makeRequest(path: Endpoint.logEvent.rawValue, body: body)
        let (data, response) = try await transport.send(req)
        
        if (400..<600).contains(response.statusCode) {
            throw APIError.from(httpStatus: response.statusCode, responseData: data)
        }
        
        // Log event might return generic response or EventResponse. 
        // Based on App/APIClient it returns EventResponse.
        return try JSONDecoder().decode(EventResponse.self, from: data)
    }
    public func exportAnalytics() async throws -> Data {
        let req = try makeRequest(path: Endpoint.exportAnalytics.rawValue, method: "GET")
        let (data, response) = try await transport.send(req)
        
        if (400..<600).contains(response.statusCode) {
             throw APIError.from(httpStatus: response.statusCode, responseData: data)
        }
        return data
    }
}
private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { self.encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
