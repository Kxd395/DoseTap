import Foundation

enum WHOOPError: LocalizedError {
    case invalidURL
    case userCancelled
    case noCallback
    case noAuthCode
    case stateMismatch
    case invalidResponse
    case httpError(Int)
    case apiError(String, String?)
    case notAuthenticated
    case noRefreshToken
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid WHOOP URL"
        case .userCancelled: return "Authorization cancelled"
        case .noCallback: return "No callback received"
        case .noAuthCode: return "No authorization code received"
        case .stateMismatch: return "Security state mismatch"
        case .invalidResponse: return "Invalid server response"
        case .httpError(let code): return "HTTP error: \(code)"
        case .apiError(let error, let desc): return desc ?? error
        case .notAuthenticated: return "Not authenticated with WHOOP"
        case .noRefreshToken: return "No refresh token available"
        case .refreshFailed: return "Failed to refresh token"
        }
    }
}

struct WHOOPTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

struct WHOOPErrorResponse: Codable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

struct WHOOPProfile: Codable {
    let userId: String?
    let firstName: String?
    let lastName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case email
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = c.decodeStringOrIntIfPresent(forKey: .userId)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        email = try c.decodeIfPresent(String.self, forKey: .email)
    }
}
