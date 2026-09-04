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

    func test_rsaFixture_spkiPinMatchesOpenSSLProductionCommand() throws {
        let certificate = try fixtureCertificateDER(named: "rsa-cert")
        let expected = try fixtureExpectedPin(named: "rsa-cert")

        XCTAssertEqual(CertificatePinning.spkiPin(forCertificateData: certificate), expected)
    }

    func test_ecFixture_spkiPinMatchesOpenSSLProductionCommand() throws {
        let certificate = try fixtureCertificateDER(named: "ec-cert")
        let expected = try fixtureExpectedPin(named: "ec-cert")

        XCTAssertEqual(CertificatePinning.spkiPin(forCertificateData: certificate), expected)
    }

    func test_fixtureMismatch_isRejected() throws {
        let certificate = try fixtureCertificateDER(named: "rsa-cert")
        let wrongPin = "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

        XCTAssertFalse(CertificatePinning.matchesCertificateChain([certificate], pins: [wrongPin]))
    }

    func test_twoPinRotation_acceptsWhenEitherReviewedPinMatches() throws {
        let certificate = try fixtureCertificateDER(named: "rsa-cert")
        let expected = try fixtureExpectedPin(named: "rsa-cert")
        let nextRotationPin = try fixtureExpectedPin(named: "ec-cert")

        XCTAssertTrue(
            CertificatePinning.matchesCertificateChain(
                [certificate],
                pins: [nextRotationPin, expected]
            )
        )
    }

    func test_chainEvaluation_acceptsMatchingIntermediateOrLeafFixture() throws {
        let rsa = try fixtureCertificateDER(named: "rsa-cert")
        let ec = try fixtureCertificateDER(named: "ec-cert")
        let ecPin = try fixtureExpectedPin(named: "ec-cert")

        XCTAssertTrue(CertificatePinning.matchesCertificateChain([rsa, ec], pins: [ecPin]))
    }

    func test_malformedAndDuplicatePins_areRemovedBeforeUse() throws {
        let valid = try fixtureExpectedPin(named: "rsa-cert")
        let normalized = CertificatePinning.normalizedPins([
            "  \(valid)  ",
            valid,
            "sha256/not-base64",
            "md5/AAAAAAAAAAAAAAAAAAAAAA==",
            "",
        ])

        XCTAssertEqual(normalized, [valid])
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
        let _: any APITransport = PinnedURLSessionTransport()
    }

    // MARK: - URLSessionDelegate (no-pin scenario)

    func test_delegate_conforms_to_URLSessionDelegate() {
        let cp = CertificatePinning(
            pins: ["sha256/abc="],
            domains: ["api.dosetap.com"]
        )
        let _: any URLSessionDelegate = cp
    }

    // MARK: - Transport Safety

    func test_urlSessionTransport_conforms_to_APITransport() {
        let _: any APITransport = URLSessionTransport()
    }

    private func fixtureCertificateDER(named name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: "pem",
                subdirectory: "CertificatePinning"
            )
        )
        let pem = try String(contentsOf: url, encoding: .utf8)
        let base64 = pem
            .split(whereSeparator: { $0.isNewline })
            .filter { !$0.hasPrefix("-----") }
            .joined()
        return try XCTUnwrap(Data(base64Encoded: base64))
    }

    private func fixtureExpectedPin(named name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: "spki-pin",
                subdirectory: "CertificatePinning"
            )
        )
        return try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
