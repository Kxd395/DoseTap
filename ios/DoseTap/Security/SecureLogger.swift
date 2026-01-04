import Foundation
import os.log

/// Secure logging utility that:
/// - Only logs in DEBUG builds
/// - Redacts sensitive data using OSLog privacy
/// - Uses structured logging categories
/// 
/// Usage:
/// ```swift
/// SecureLogger.shared.debug("User action", category: .userAction)
/// SecureLogger.shared.info("API call to \(endpoint, privacy: .public)")
/// SecureLogger.shared.error("Failed to connect", error: error)
/// ```
///
/// Migration from print():
/// Replace: print("message")
/// With:    debugLog("message")
/// Or:      logInfo("message", category: .general)
///
@available(iOS 14.0, watchOS 7.0, *)
public final class SecureLogger: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = SecureLogger()
    
    // MARK: - Log Categories
    
    public enum Category: String {
        case general = "DoseTap"
        case network = "DoseTap.Network"
        case storage = "DoseTap.Storage"
        case auth = "DoseTap.Auth"
        case health = "DoseTap.Health"
        case userAction = "DoseTap.UserAction"
        case navigation = "DoseTap.Navigation"
        case security = "DoseTap.Security"
        
        var osLog: OSLog {
            OSLog(subsystem: "com.dosetap.app", category: self.rawValue)
        }
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Log debug message (only in DEBUG builds)
    public func debug(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        os_log(.debug, log: category.osLog, "%{public}@ [%{public}@:%{public}d]", message, fileName(from: file), line)
        #endif
    }
    
    /// Log info message
    public func info(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        os_log(.info, log: category.osLog, "%{public}@", message)
        #endif
    }
    
    /// Log warning message
    public func warning(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        os_log(.default, log: category.osLog, "⚠️ %{public}@", message)
        #endif
    }
    
    /// Log error message
    public func error(
        _ message: String,
        error: Error? = nil,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        if let error = error {
            os_log(.error, log: category.osLog, "❌ %{public}@: %{public}@", message, String(describing: error))
        } else {
            os_log(.error, log: category.osLog, "❌ %{public}@", message)
        }
        #endif
    }
    
    /// Log security-related event (always redacted in release)
    public func security(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        os_log(.default, log: Category.security.osLog, "🔐 %{private}@", message)
        #endif
    }
    
    /// Log network request (redacts sensitive headers/body)
    public func network(
        method: String,
        path: String,
        statusCode: Int? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        if let statusCode = statusCode {
            os_log(.info, log: Category.network.osLog, "%{public}@ %{public}@ → %{public}d", method, path, statusCode)
        } else {
            os_log(.info, log: Category.network.osLog, "%{public}@ %{public}@", method, path)
        }
        #endif
    }
    
    /// Log user action with privacy protection
    public func userAction(
        _ action: String,
        details: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        if let details = details {
            os_log(.info, log: Category.userAction.osLog, "👤 %{public}@: %{private}@", action, details)
        } else {
            os_log(.info, log: Category.userAction.osLog, "👤 %{public}@", action)
        }
        #endif
    }
    
    // MARK: - Helpers
    
    private func fileName(from path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

// MARK: - Convenience Global Functions

/// Log debug message (only in DEBUG builds)
public func logDebug(_ message: String, category: SecureLogger.Category = .general) {
    if #available(iOS 14.0, watchOS 7.0, *) {
        SecureLogger.shared.debug(message, category: category)
    }
}

/// Log info message
public func logInfo(_ message: String, category: SecureLogger.Category = .general) {
    if #available(iOS 14.0, watchOS 7.0, *) {
        SecureLogger.shared.info(message, category: category)
    }
}

/// Log error message
public func logError(_ message: String, error: Error? = nil, category: SecureLogger.Category = .general) {
    if #available(iOS 14.0, watchOS 7.0, *) {
        SecureLogger.shared.error(message, error: error, category: category)
    }
}

// MARK: - Legacy Print Replacement

/// Safe print replacement that only outputs in DEBUG builds
/// Use this as a drop-in replacement for existing print() calls during migration
public func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    let output = items.map { String(describing: $0) }.joined(separator: separator)
    Swift.print(output, terminator: terminator)
    #endif
}

/// Drop-in replacement for print() that only works in DEBUG builds
/// Usage: Replace `print("message")` with `debugLog("message")`
public func debugLog(_ message: String, file: String = #file, line: Int = #line) {
    #if DEBUG
    let filename = (file as NSString).lastPathComponent
    Swift.print("[\(filename):\(line)] \(message)")
    #endif
}

/// Categorized logging that only works in DEBUG builds
/// Usage: Replace `print("API call")` with `log("API call", category: .network)`
public func log(_ message: String, category: SecureLogger.Category, file: String = #file, line: Int = #line) {
    #if DEBUG
    if #available(iOS 14.0, watchOS 7.0, *) {
        SecureLogger.shared.debug(message, category: category, file: file, line: line)
    } else {
        let filename = (file as NSString).lastPathComponent
        Swift.print("[\(category.rawValue)] [\(filename):\(line)] \(message)")
    }
    #endif
}
