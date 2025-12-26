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
public struct DoseResponse: Codable {
    public let eventId: String
    public let type: String
    public let at: String
    public let dose2Window: WindowResponse?
    
    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case type, at
        case dose2Window = "dose2_window"
    }
}

public struct WindowResponse: Codable {
    public let min: String
    public let max: String
}

public struct SnoozeResponse: Codable {
    public let eventId: String
    public let minutes: Int
    public let newTargetAt: String
    
    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case minutes
        case newTargetAt = "new_target_at"
    }
}

public struct SkipResponse: Codable {
    public let eventId: String
    public let reason: String?
    
    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case reason
    }
}

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
    public enum Endpoint: String, CaseIterable { 
        case takeDose = "/doses/take"
        case skipDose = "/doses/skip"
        case snoozeDose = "/doses/snooze"
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
    private struct DoseBody: Encodable { let type: String; let at: String }
    private struct SnoozeBody: Encodable { let minutes: Int; let at: String }
    private struct SkipBody: Encodable { let sequence: Int; let reason: String?; let at: String }
    private struct LogEventBody: Encodable { let event: String; let at: String }

    @discardableResult
    public func takeDose(type: String, at date: Date = Date()) async throws -> DoseResponse {
        let body = DoseBody(type: type, at: ISO8601DateFormatter().string(from: date))
        let req = try makeRequest(path: Endpoint.takeDose.rawValue, body: body)
        let (data, response) = try await transport.send(req)
        
        if (400..<600).contains(response.statusCode) {
            throw APIError.from(httpStatus: response.statusCode, responseData: data)
        }
        return try JSONDecoder().decode(DoseResponse.self, from: data)
    }
    
    @discardableResult
    public func snooze(minutes: Int, at date: Date = Date()) async throws -> SnoozeResponse {
        let body = SnoozeBody(minutes: minutes, at: ISO8601DateFormatter().string(from: date))
        let req = try makeRequest(path: Endpoint.snoozeDose.rawValue, body: body)
        let (data, response) = try await transport.send(req)
        
        if (400..<600).contains(response.statusCode) {
            throw APIError.from(httpStatus: response.statusCode, responseData: data)
        }
        return try JSONDecoder().decode(SnoozeResponse.self, from: data)
    }
    
    @discardableResult
    public func skipDose(sequence: Int = 2, reason: String? = nil, at date: Date = Date()) async throws -> SkipResponse {
        let body = SkipBody(sequence: sequence, reason: reason, at: ISO8601DateFormatter().string(from: date))
        let req = try makeRequest(path: Endpoint.skipDose.rawValue, body: body)
        let (data, response) = try await transport.send(req)
        
        if (400..<600).contains(response.statusCode) {
            throw APIError.from(httpStatus: response.statusCode, responseData: data)
        }
        return try JSONDecoder().decode(SkipResponse.self, from: data)
    }
    
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
