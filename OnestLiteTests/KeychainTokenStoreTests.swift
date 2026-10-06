import XCTest
@testable import OnestLite

final class KeychainTokenStoreTests: XCTestCase {
    private let store = KeychainTokenStore(service: "com.onest.OnestLite.tests.\(UUID().uuidString)")

    override func tearDown() {
        try? store.clear()
        super.tearDown()
    }

    func testSaveLoadOverwriteAndClear() throws {
        XCTAssertNil(try store.load())

        let first = StoredSession(accessToken: "a1", refreshToken: "r1",
                                  accessTokenExpiresAt: Date(timeIntervalSince1970: 1_800_000_060))
        try store.save(first)
        XCTAssertEqual(try store.load(), first)

        let second = StoredSession(accessToken: "a2", refreshToken: "r2",
                                   accessTokenExpiresAt: Date(timeIntervalSince1970: 1_800_000_120))
        try store.save(second)
        XCTAssertEqual(try store.load(), second)

        try store.clear()
        XCTAssertNil(try store.load())
        XCTAssertNoThrow(try store.clear(), "Borrar dos veces no debe fallar")
    }
}
