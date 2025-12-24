import Foundation

// MARK: - API Error Types

/// Unified error types for DoseTap API operations.
/// Maps HTTP status codes and server error responses to typed errors.
public enum APIError: Error, LocalizedError, Equatable {
    case windowExceeded
    case snoozeLimit
    case dose1Required
    case alreadyTaken
    case rateLimit
    case deviceNotRegistered
    case offline
    case invalidResponse
    case decoding(String)
    case networkError(String)
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .windowExceeded: return "Window exceeded. Take now or Skip."
        case .snoozeLimit: return "Snooze limit reached for tonight"
        case .dose1Required: return "Log Dose 1 first"
        case .alreadyTaken: return "Dose 2 already resolved"
        case .rateLimit: return "Too many taps. Try again in a moment."
        case .deviceNotRegistered: return "Device not registered."
        case .offline: return "No internet connection."
        case .invalidResponse: return "Invalid server response"
        case .decoding(let msg): return "Decoding error: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        case .unknown(let msg): return "Unknown error: \(msg)"
        }
    }
    
    /// Maps HTTP status codes and optional response data to typed errors.
    /// - Parameters:
    ///   - httpStatus: The HTTP status code from the response
    ///   - responseData: Optional response body for extracting error codes
    /// - Returns: A typed APIError
    public static func from(httpStatus: Int, responseData: Data? = nil) -> APIError {
        switch httpStatus {
        case 422:
            if let data = responseData,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorCode = json["error_code"] as? String {
                switch errorCode {
                case "WINDOW_EXCEEDED": return .windowExceeded
                case "SNOOZE_LIMIT": return .snoozeLimit
                case "DOSE1_REQUIRED": return .dose1Required
                default: return .unknown("422: \(errorCode)")
                }
            }
            return .windowExceeded
        case 409: return .alreadyTaken
        case 401: return .deviceNotRegistered
        case 429: return .rateLimit
        default: return .unknown("HTTP \(httpStatus)")
        }
    }
    
    // Equatable conformance for networkError case
    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.windowExceeded, .windowExceeded),
             (.snoozeLimit, .snoozeLimit),
             (.dose1Required, .dose1Required),
             (.alreadyTaken, .alreadyTaken),
             (.rateLimit, .rateLimit),
             (.deviceNotRegistered, .deviceNotRegistered),
             (.offline, .offline),
             (.invalidResponse, .invalidResponse):
            return true
        case (.decoding(let a), .decoding(let b)):
            return a == b
        case (.networkError(let a), .networkError(let b)):
            return a == b
        case (.unknown(let a), .unknown(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - API Error Payload

/// Server error response structure for parsing API error details.
public struct APIErrorPayload: Decodable {
    public let code: String
    public let message: String?
    
    enum CodingKeys: String, CodingKey {
        case code = "error_code"
        case message
    }
}

// MARK: - Error Mapper

/// Utility for mapping raw API responses to typed errors.
public enum APIErrorMapper {
    /// Maps response data and status code to a typed APIError.
    public static func map(data: Data, status: Int) -> APIError {
        APIError.from(httpStatus: status, responseData: data)
    }
}
