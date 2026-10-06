import Foundation
@testable import OnestLite

/// Reloj controlable para simular el paso del tiempo sin esperar.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = start
    }

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// Envuelve un transporte, cuenta las llamadas por ruta y opcionalmente retrasa el refresh
/// para garantizar que las peticiones concurrentes se solapen.
final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let inner: HTTPTransport
    private let refreshDelay: UInt64
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    init(inner: HTTPTransport, refreshDelayNanoseconds: UInt64 = 0) {
        self.inner = inner
        self.refreshDelay = refreshDelayNanoseconds
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        record(key)
        if key == "POST /auth/refresh", refreshDelay > 0 {
            try await Task.sleep(nanoseconds: refreshDelay)
        }
        return try await inner.send(request)
    }

    func count(_ key: String) -> Int {
        lock.withLock { counts[key, default: 0] }
    }

    private func record(_ key: String) {
        lock.withLock { counts[key, default: 0] += 1 }
    }
}

/// Backend + sesión + cliente conectados con relojes independientes: el reloj del servidor puede
/// avanzar sin que el cliente lo note, que es justo el caso "el token expiró y recibo 401".
struct TestHarness {
    let serverClock = TestClock()
    let clientClock: TestClock
    let backend: MockBackend
    let transport: RecordingTransport
    let store = InMemoryTokenStore()
    let auth: AuthSession
    let client: APIClient
    let baseURL = URL(string: "https://api.test")!

    init(configuration: MockBackend.Configuration = .instant,
         refreshDelayNanoseconds: UInt64 = 20_000_000,
         random: @escaping @Sendable () -> Double = { 0.99 }) {
        let serverClock = serverClock
        let clientClock = TestClock(serverClock.now)
        self.clientClock = clientClock
        backend = MockBackend(configuration: configuration,
                              now: { serverClock.now },
                              random: random)
        transport = RecordingTransport(inner: MockTransport(backend: backend),
                                       refreshDelayNanoseconds: refreshDelayNanoseconds)
        auth = AuthSession(baseURL: baseURL, transport: transport, store: store, now: { clientClock.now })
        client = APIClient(baseURL: baseURL, transport: transport, auth: auth)
    }

    func login() async throws {
        try await auth.login(username: MockBackend.demoUsername, password: MockBackend.demoPassword)
    }

    /// Avanza ambos relojes.
    func advance(_ seconds: TimeInterval) {
        serverClock.advance(seconds)
        clientClock.advance(seconds)
    }
}

/// Repositorio falso con respuestas programables.
final class FakeLoanRepository: LoanRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _loansResults: [Result<[Loan], Error>] = []
    private var _quoteResult: Result<LoanQuote, Error> = .failure(APIError.network)
    private var _createResults: [Result<Loan, Error>] = []
    private var _createdKeys: [String] = []

    var createdKeys: [String] { lock.withLock { _createdKeys } }

    func enqueueLoans(_ result: Result<[Loan], Error>) { lock.withLock { _loansResults.append(result) } }
    func setQuote(_ result: Result<LoanQuote, Error>) { lock.withLock { _quoteResult = result } }
    func enqueueCreate(_ result: Result<Loan, Error>) { lock.withLock { _createResults.append(result) } }

    func loans() async throws -> [Loan] {
        try lock.withLock { _loansResults.isEmpty ? .success([]) : _loansResults.removeFirst() }.get()
    }

    func loan(id: String) async throws -> LoanDetail {
        throw APIError.notFound
    }

    func quote(_ terms: LoanTerms) async throws -> LoanQuote {
        try lock.withLock { _quoteResult }.get()
    }

    func create(_ terms: LoanTerms, idempotencyKey: String) async throws -> Loan {
        try lock.withLock {
            _createdKeys.append(idempotencyKey)
            return _createResults.isEmpty ? .failure(APIError.network) : _createResults.removeFirst()
        }.get()
    }
}

enum Fixtures {
    static func loan(id: String = "L-1", status: LoanStatus = .enRevision) -> Loan {
        Loan(id: id, amountCents: 2_500_000, outstandingBalanceCents: 2_500_000, termMonths: 12,
             annualRatePercent: 24, nextPaymentDate: nil, status: status,
             createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    static let quote = LoanQuote(amountCents: 2_500_000, termMonths: 12, monthlyPaymentCents: 236_000,
                                 annualRatePercent: 24, totalCostCents: 2_832_000)
}
