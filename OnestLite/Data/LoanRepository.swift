import Foundation

protocol LoanRepository: Sendable {
    func loans() async throws -> [Loan]
    func loan(id: String) async throws -> LoanDetail
    func quote(_ terms: LoanTerms) async throws -> LoanQuote
    /// `idempotencyKey` identifica *esta* solicitud: reintentar con la misma llave nunca duplica el préstamo.
    func create(_ terms: LoanTerms, idempotencyKey: String) async throws -> Loan
}

struct RetryPolicy: Sendable {
    let maxAttempts: Int
    let baseDelay: TimeInterval

    static let none = RetryPolicy(maxAttempts: 1, baseDelay: 0)
    static let standard = RetryPolicy(maxAttempts: 3, baseDelay: 0.4)

    func delay(afterAttempt attempt: Int) -> TimeInterval {
        baseDelay * Double(attempt)
    }
}

struct APILoanRepository: LoanRepository {
    private let client: APIClient
    private let retryPolicy: RetryPolicy

    init(client: APIClient, retryPolicy: RetryPolicy = .standard) {
        self.client = client
        self.retryPolicy = retryPolicy
    }

    func loans() async throws -> [Loan] {
        try await client.send(.loans)
    }

    func loan(id: String) async throws -> LoanDetail {
        try await client.send(.loan(id: id))
    }

    func quote(_ terms: LoanTerms) async throws -> LoanQuote {
        try await client.send(.quote(terms))
    }

    /// Reintenta automáticamente 5xx y fallos de red reusando la misma llave de idempotencia,
    /// por lo que un reintento después de un 500 (o de una respuesta perdida) es seguro.
    func create(_ terms: LoanTerms, idempotencyKey: String) async throws -> Loan {
        var attempt = 1
        while true {
            do {
                return try await client.send(.createLoan(terms, idempotencyKey: idempotencyKey))
            } catch let error as APIError where error.isRetryable && attempt < retryPolicy.maxAttempts {
                let delay = retryPolicy.delay(afterAttempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            }
        }
    }
}
