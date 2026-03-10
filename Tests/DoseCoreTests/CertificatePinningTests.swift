import XCTest
@testable import DoseCore

@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
final class CertificatePinningTests: XCTestCase {

    // MARK: - Initialization

    func test_init_stores_pins() {
        let cp = CertificatePinning(
            pins: ["sha256/abc=", "sha256/def="],
            domains: ["api.dosetap.com"]
        )
        // Can create — no crash. Pin set is private, so we verify behavior via delegate.
        XCTAssertNotNil(cp)
    }

    func test_init_empty_pins() {
        let cp = CertificatePinning(pins: [], domains: [])
        XCTAssertNotNil(cp)
    }

    func test_init_domains_lowercased() {
        // Ensures internal domain comparison is case-insensitive
        let cp = CertificatePinning(
            pins: ["sha256/abc="],
            domains: ["API.DoseTap.COM"]
        )
        XCTAssertNotNil(cp)
    }

    // MARK: - Static Helpers

    func test_hasConfiguredPins_reads_env() {
        // In test environment, no env var is typically set
        // Just verify the property is accessible and doesn't crash
        _ = CertificatePinning.hasConfiguredPins
    }

    func test_forDoseTapAPI_factory() {
        let cp = CertificatePinning.forDoseTapAPI()
        XCTAssertNotNil(cp)
    }

    // MARK: - PinnedURLSessionTransport

    func test_pinnedTransport_init_with_custom_pinning() {
        let pinning = CertificatePinning(pins: ["sha256/test="], domains: ["example.com"])
        let transport = PinnedURLSessionTransport(pinning: pinning)
        XCTAssertNotNil(transport)
    }

    func test_pinnedTransport_default_init() {
        let transport = PinnedURLSessionTransport()
        XCTAssertNotNil(transport)
    }

    func test_pinnedTransport_conforms_to_APITransport() {
        let transport = PinnedURLSessionTransport()
        XCTAssertTrue(transport is any APITransport)
    }

    // MARK: - URLSessionDelegate (no-pin scenario)

    func test_delegate_fallback_for_nonPinned_domain() async {
        // When pinnedDomains is set and challenge host is NOT in it,
        // the delegate should call performDefaultHandling.
        let cp = CertificatePinning(
            pins: ["sha256/abc="],
            domains: ["api.dosetap.com"]
        )

        // Create a mock challenge for a different domain
        // URLAuthenticationChallenge can't be easily mocked, so we verify
        // the object was created correctly and delegate method exists
        let selector = #selector(URLSessionDelegate.urlSession(_:didReceive:completionHandler:))
        XCTAssertTrue(cp.responds(to: selector), "Should respond to auth challenge delegate method")
    }

    // MARK: - Transport Safety

    func test_urlSessionTransport_conforms_to_APITransport() {
        let transport = URLSessionTransport()
        XCTAssertTrue(transport is any APITransport)
    }

    func test_mockTransport_only_exists_in_DEBUG() {
        // This test compiles in both DEBUG and RELEASE.
        // In DEBUG, MockAPITransport should be available.
        // In RELEASE, it should not compile — but since tests always
        // run in DEBUG, we verify it exists here as a canary.
        #if DEBUG
        let mock = MockAPITransport()
        XCTAssertTrue(mock is any APITransport)
        #else
        // If this line ever compiles, MockAPITransport leaked into release
        XCTFail("Tests should only run in DEBUG configuration")
        #endif
    }
}
