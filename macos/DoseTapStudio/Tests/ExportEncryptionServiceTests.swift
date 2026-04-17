import XCTest
@testable import DoseTapStudio

final class ExportEncryptionServiceTests: XCTestCase {
    func testEncryptionRoundTripRestoresOriginalPayload() throws {
        let service = ExportEncryptionService()
        let original = Data("sensitive export payload".utf8)

        let encrypted = try service.encrypt(
            data: original,
            fileName: "DoseTap-Provider-Summary.txt",
            passphrase: "correct horse battery staple"
        )
        let decrypted = try service.decrypt(
            encryptedData: encrypted,
            passphrase: "correct horse battery staple"
        )

        XCTAssertNotEqual(encrypted, original)
        XCTAssertEqual(decrypted, original)
        XCTAssertTrue(String(decoding: encrypted, as: UTF8.self).contains("AES.GCM+SHA256"))
    }

    func testEncryptionRejectsEmptyPassphrase() {
        let service = ExportEncryptionService()

        XCTAssertThrowsError(
            try service.encrypt(data: Data("payload".utf8), fileName: "test.txt", passphrase: "")
        ) { error in
            XCTAssertEqual(error.localizedDescription, ExportEncryptionError.emptyPassphrase.localizedDescription)
        }
    }
}
