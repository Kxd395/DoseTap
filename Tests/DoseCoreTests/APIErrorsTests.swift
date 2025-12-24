import XCTest
@testable import DoseCore

final class APIErrorsTests: XCTestCase {
    
    // MARK: - HTTP Status Code Mapping
    
    func testErrorMapping401ReturnsDeviceNotRegistered() {
        let error = APIError.from(httpStatus: 401)
        XCTAssertEqual(error, .deviceNotRegistered)
    }
    
    func testErrorMapping409ReturnsAlreadyTaken() {
        let error = APIError.from(httpStatus: 409)
        XCTAssertEqual(error, .alreadyTaken)
    }
    
    func testErrorMapping429ReturnsRateLimit() {
        let error = APIError.from(httpStatus: 429)
        XCTAssertEqual(error, .rateLimit)
    }
    
    func testErrorMapping422DefaultReturnsWindowExceeded() {
        let error = APIError.from(httpStatus: 422)
        XCTAssertEqual(error, .windowExceeded)
    }
    
    func testErrorMapping500ReturnsUnknown() {
        let error = APIError.from(httpStatus: 500)
        if case .unknown(let msg) = error {
            XCTAssertTrue(msg.contains("500"))
        } else {
            XCTFail("Expected unknown error")
        }
    }
    
    // MARK: - Error Code Parsing from Response Data
    
    func testErrorMapping422WithWindowExceededCode() {
        let json = """
        {"error_code": "WINDOW_EXCEEDED", "message": "Window has closed"}
        """.data(using: .utf8)!
        
        let error = APIError.from(httpStatus: 422, responseData: json)
        XCTAssertEqual(error, .windowExceeded)
    }
    
    func testErrorMapping422WithSnoozeLimitCode() {
        let json = """
        {"error_code": "SNOOZE_LIMIT", "message": "Max snoozes reached"}
        """.data(using: .utf8)!
        
        let error = APIError.from(httpStatus: 422, responseData: json)
        XCTAssertEqual(error, .snoozeLimit)
    }
    
    func testErrorMapping422WithDose1RequiredCode() {
        let json = """
        {"error_code": "DOSE1_REQUIRED", "message": "Take dose 1 first"}
        """.data(using: .utf8)!
        
        let error = APIError.from(httpStatus: 422, responseData: json)
        XCTAssertEqual(error, .dose1Required)
    }
    
    func testErrorMapping422WithUnknownCodeReturnsUnknown() {
        let json = """
        {"error_code": "SOME_OTHER_ERROR", "message": "Something else"}
        """.data(using: .utf8)!
        
        let error = APIError.from(httpStatus: 422, responseData: json)
        if case .unknown(let msg) = error {
            XCTAssertTrue(msg.contains("SOME_OTHER_ERROR"))
        } else {
            XCTFail("Expected unknown error with code")
        }
    }
    
    func testErrorMapping422WithInvalidJSONReturnsWindowExceeded() {
        let invalidJson = "not json".data(using: .utf8)!
        
        let error = APIError.from(httpStatus: 422, responseData: invalidJson)
        XCTAssertEqual(error, .windowExceeded) // Falls back to default 422 handling
    }
    
    // MARK: - Error Descriptions
    
    func testErrorDescriptions() {
        XCTAssertNotNil(APIError.windowExceeded.errorDescription)
        XCTAssertNotNil(APIError.snoozeLimit.errorDescription)
        XCTAssertNotNil(APIError.dose1Required.errorDescription)
        XCTAssertNotNil(APIError.alreadyTaken.errorDescription)
        XCTAssertNotNil(APIError.rateLimit.errorDescription)
        XCTAssertNotNil(APIError.deviceNotRegistered.errorDescription)
        XCTAssertNotNil(APIError.offline.errorDescription)
        XCTAssertNotNil(APIError.invalidResponse.errorDescription)
        XCTAssertNotNil(APIError.decoding("test").errorDescription)
        XCTAssertNotNil(APIError.networkError("test").errorDescription)
        XCTAssertNotNil(APIError.unknown("test").errorDescription)
    }
    
    // MARK: - APIErrorMapper
    
    func testAPIErrorMapperMapsCorrectly() {
        let json = """
        {"error_code": "SNOOZE_LIMIT"}
        """.data(using: .utf8)!
        
        let error = APIErrorMapper.map(data: json, status: 422)
        XCTAssertEqual(error, .snoozeLimit)
    }
}
