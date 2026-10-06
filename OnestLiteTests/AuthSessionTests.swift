import XCTest
@testable import OnestLite

final class AuthSessionTests: XCTestCase {
    func testLoginStoresSession() async throws {
        let harness = TestHarness()
        try await harness.login()

        let stored = try XCTUnwrap(try harness.store.load())
        XCTAssertFalse(stored.accessToken.isEmpty)
        XCTAssertFalse(stored.refreshToken.isEmpty)
        let hasSession = await harness.auth.hasSession()
        XCTAssertTrue(hasSession)
    }

    func testInvalidCredentialsThrowsAndStoresNothing() async throws {
        let harness = TestHarness()
        do {
            try await harness.auth.login(username: "demo", password: "wrong")
            XCTFail("Debió fallar")
        } catch {
            XCTAssertEqual(error as? APIError, .invalidCredentials)
        }
        XCTAssertNil(try harness.store.load())
    }

    /// Con refresh tokens rotativos, dos renovaciones simultáneas serían un bug real.
    func testConcurrentExpiredTokenRequestsTriggerASingleRefresh() async throws {
        let harness = TestHarness()
        try await harness.login()
        let original = try XCTUnwrap(try harness.store.load()).accessToken
        harness.advance(61) // el access token (60 s) venció para todos

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<20 {
                group.addTask { try await harness.auth.validAccessToken() }
            }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }

        XCTAssertEqual(harness.transport.count("POST /auth/refresh"), 1)
        XCTAssertEqual(Set(tokens).count, 1, "Todos deben recibir el mismo token nuevo")
        XCTAssertNotEqual(tokens.first, original)
    }

    /// El cliente cree que el token sigue vigente, el servidor responde 401 en todas las peticiones
    /// a la vez; deben compartir una sola renovación y completarse bien.
    func testConcurrent401sShareOneRefreshAndAllRequestsSucceed() async throws {
        let harness = TestHarness()
        try await harness.login()
        harness.serverClock.advance(61) // solo el servidor lo sabe

        let counts = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<10 {
                group.addTask { try await harness.client.send(.loans, as: [Loan].self).count }
            }
            return try await group.reduce(into: [Int]()) { $0.append($1) }
        }

        XCTAssertEqual(counts.count, 10)
        XCTAssertTrue(counts.allSatisfy { $0 == 5 })
        XCTAssertEqual(harness.transport.count("POST /auth/refresh"), 1)
    }

    func testRefreshTokenExpiredForcesNewLogin() async throws {
        let harness = TestHarness()
        try await harness.login()
        harness.advance(601) // vencen access (60 s) y refresh (600 s)

        var expirations = harness.auth.sessionExpirations.makeAsyncIterator()
        do {
            _ = try await harness.client.send(.loans, as: [Loan].self)
            XCTFail("Debió fallar")
        } catch {
            XCTAssertEqual(error as? APIError, .sessionExpired)
        }

        XCTAssertNil(try harness.store.load(), "La sesión vencida debe borrarse del almacén")
        let notified: Void? = await expirations.next()
        XCTAssertNotNil(notified)
    }

    func testLogoutDuringRefreshDoesNotResurrectCredentials() async throws {
        let harness = TestHarness(refreshDelayNanoseconds: 100_000_000)
        try await harness.login()
        harness.advance(61)

        async let pending = harness.auth.validAccessToken()
        try await Task.sleep(nanoseconds: 30_000_000) // la renovación ya salió
        await harness.auth.logout()

        do {
            _ = try await pending
            XCTFail("La renovación debió descartarse")
        } catch {
            // Cancelada por el logout, o descartada por la época si la respuesta llegó igual.
            XCTAssertTrue(error is CancellationError || (error as? APIError) == .notAuthenticated, "\(error)")
        }
        XCTAssertNil(try harness.store.load(), "Ninguna credencial debe sobrevivir al logout")
    }

    func testRequestsWithoutSessionFailAsNotAuthenticated() async {
        let harness = TestHarness()
        do {
            _ = try await harness.client.send(.loans, as: [Loan].self)
            XCTFail("Debió fallar")
        } catch {
            XCTAssertEqual(error as? APIError, .notAuthenticated)
        }
    }
}
