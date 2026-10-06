import XCTest
@testable import OnestLite

/// Verifica que el backend simulado cumple el contrato del enunciado, a través del cliente real.
final class MockBackendTests: XCTestCase {
    private func makeLoggedInHarness(random: @escaping @Sendable () -> Double = { 0.99 }) async throws -> TestHarness {
        let harness = TestHarness(random: random)
        try await harness.login()
        return harness
    }

    func testListReturnsSeededLoans() async throws {
        let harness = try await makeLoggedInHarness()
        let loans: [Loan] = try await harness.client.send(.loans)
        XCTAssertEqual(Set(loans.map(\.status)), Set(LoanStatus.allCases))
    }

    func testDetailIncludesScheduleAndUnknownLoanIs404() async throws {
        let harness = try await makeLoggedInHarness()
        let detail: LoanDetail = try await harness.client.send(.loan(id: "L-1001"))
        XCTAssertEqual(detail.schedule.count, 12)
        XCTAssertEqual(detail.schedule.filter(\.isPaid).count, 4)

        do {
            let _: LoanDetail = try await harness.client.send(.loan(id: "nope"))
            XCTFail("Debió fallar")
        } catch {
            XCTAssertEqual(error as? APIError, .notFound)
        }
    }

    func testQuoteOutOfRangeIs422() async throws {
        let harness = try await makeLoggedInHarness()
        for terms in [LoanTerms(amountCents: 4_999 * 100, termMonths: 12),
                      LoanTerms(amountCents: 100_001 * 100, termMonths: 12),
                      LoanTerms(amountCents: 10_000 * 100, termMonths: 2),
                      LoanTerms(amountCents: 10_000 * 100, termMonths: 25)] {
            do {
                let _: LoanQuote = try await harness.client.send(.quote(terms))
                XCTFail("Debió fallar para \(terms)")
            } catch {
                guard case .validation = error as? APIError else {
                    return XCTFail("Se esperaba 422, llegó \(error)")
                }
            }
        }
    }

    func testQuoteIsConsistent() async throws {
        let harness = try await makeLoggedInHarness()
        let quote: LoanQuote = try await harness.client.send(.quote(LoanTerms(amountCents: 2_500_000, termMonths: 12)))
        XCTAssertEqual(quote.annualRatePercent, 24)
        XCTAssertEqual(quote.totalCostCents, quote.monthlyPaymentCents * 12)
        XCTAssertGreaterThan(quote.totalCostCents, 2_500_000)
    }

    func testCreateWithSameIdempotencyKeyReturnsSameLoan() async throws {
        let harness = try await makeLoggedInHarness()
        let terms = LoanTerms(amountCents: 3_000_000, termMonths: 6)

        let first: Loan = try await harness.client.send(.createLoan(terms, idempotencyKey: "key-1"))
        let second: Loan = try await harness.client.send(.createLoan(terms, idempotencyKey: "key-1"))
        let third: Loan = try await harness.client.send(.createLoan(terms, idempotencyKey: "key-2"))

        XCTAssertEqual(first.status, .enRevision)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first.id, third.id)
        let all: [Loan] = try await harness.client.send(.loans)
        XCTAssertEqual(all.count, 7)
    }

    func testCreateRequiresIdempotencyKey() async throws {
        let harness = try await makeLoggedInHarness()
        let endpoint = Endpoint(method: .post, path: "/loans",
                                body: JSONCoding.encode(LoanTerms(amountCents: 3_000_000, termMonths: 6)))
        do {
            let _: Loan = try await harness.client.send(endpoint)
            XCTFail("Debió fallar")
        } catch {
            guard case .badRequest = error as? APIError else { return XCTFail("Llegó \(error)") }
        }
    }

    func testIntermittentFailureThenRetryWithSameKeyCreatesExactlyOneLoan() async throws {
        // Primer intento cae en el 500 aleatorio; el segundo no.
        let rolls = RollSequence([0.1, 0.9])
        let harness = try await makeLoggedInHarness(random: { rolls.next() })
        let terms = LoanTerms(amountCents: 3_000_000, termMonths: 6)
        let repository = APILoanRepository(client: harness.client, retryPolicy: .none)

        do {
            _ = try await repository.create(terms, idempotencyKey: "k")
            XCTFail("El primer intento debía fallar con 500")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 500))
        }
        let loan = try await repository.create(terms, idempotencyKey: "k")
        let again = try await repository.create(terms, idempotencyKey: "k")

        XCTAssertEqual(loan, again)
        let all: [Loan] = try await harness.client.send(.loans)
        XCTAssertEqual(all.filter { $0.id == loan.id }.count, 1)
    }

    func testRepositoryRetriesServerErrorsAutomatically() async throws {
        let rolls = RollSequence([0.1, 0.1, 0.9])
        let harness = try await makeLoggedInHarness(random: { rolls.next() })
        let repository = APILoanRepository(client: harness.client,
                                           retryPolicy: RetryPolicy(maxAttempts: 3, baseDelay: 0))
        let loan = try await repository.create(LoanTerms(amountCents: 3_000_000, termMonths: 6), idempotencyKey: "k")
        XCTAssertEqual(loan.status, .enRevision)
        XCTAssertEqual(harness.transport.count("POST /loans"), 3)
    }
}

final class RollSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double]

    init(_ values: [Double]) { self.values = values }

    func next() -> Double {
        lock.withLock { values.count > 1 ? values.removeFirst() : (values.first ?? 0.99) }
    }
}
