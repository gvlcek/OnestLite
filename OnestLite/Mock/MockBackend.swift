import CryptoKit
import Foundation

struct MockRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

struct MockResponse: Sendable {
    let status: Int
    let body: Data
}

/// Servidor simulado que implementa el contrato de la API del enunciado.
///
/// - Los tokens son stateless (JSON firmado con HMAC-SHA256), así la sesión guardada en Keychain
///   sigue siendo válida aunque la app se reinicie y el backend en memoria empiece de cero.
/// - Lo que el usuario crea (préstamos + llaves de idempotencia) se persiste con `persistence`.
actor MockBackend {
    struct Configuration: Sendable {
        var accessTokenLifetime: TimeInterval = 60
        var refreshTokenLifetime: TimeInterval = 600
        /// Latencia aleatoria de GET /loans.
        var listLatency: ClosedRange<TimeInterval> = 0.5...2.0
        /// Probabilidad de 500 en POST /loans (1 de cada 4).
        var createFailureProbability: Double = 0.25

        /// Sin latencia artificial (pruebas y `ONEST_FAST_MOCK`).
        static var instant: Configuration {
            var configuration = Configuration()
            configuration.listLatency = 0...0
            return configuration
        }
    }

    struct Persistence: Sendable {
        let load: @Sendable () -> Data?
        let save: @Sendable (Data) -> Void
    }

    static let demoUsername = "demo"
    static let demoPassword = "demo1234"

    private struct Record: Codable {
        let owner: String
        let loan: Loan
        let schedule: [Installment]
    }

    private struct Snapshot: Codable {
        var created: [Record]
        var idempotency: [String: String]
        var nextID: Int
    }

    private struct TokenClaims: Codable {
        let kind: String
        let subject: String
        let expiresAt: Date
        let id: String
    }

    private enum TokenKind {
        static let access = "access"
        static let refresh = "refresh"
    }

    private let configuration: Configuration
    private let now: @Sendable () -> Date
    private let random: @Sendable () -> Double
    private let persistence: Persistence?
    private let signingKey = SymmetricKey(data: Data("onest-lite-mock-signing-key".utf8))

    private var seeded: [Record] = []
    private var snapshot = Snapshot(created: [], idempotency: [:], nextID: 2001)

    init(configuration: Configuration = Configuration(),
         persistence: Persistence? = nil,
         now: @escaping @Sendable () -> Date = { Date() },
         random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }) {
        self.configuration = configuration
        self.persistence = persistence
        self.now = now
        self.random = random
        if let data = persistence?.load(),
           let stored = try? JSONCoding.makeDecoder().decode(Snapshot.self, from: data) {
            snapshot = stored
        }
        seeded = Self.makeSeedRecords(owner: Self.demoUsername, now: now())
    }

    // MARK: Routing

    func handle(_ request: MockRequest) async throws -> MockResponse {
        let segments = request.path.split(separator: "/").map(String.init)
        let method = request.method.uppercased()

        if method == "POST", segments == ["auth", "login"] { return login(request) }
        if method == "POST", segments == ["auth", "refresh"] { return refresh(request) }

        guard let user = authenticatedUser(request) else {
            return failure(401, code: "unauthorized", message: "Token inválido o expirado.")
        }

        if method == "GET", segments == ["loans"] {
            let latency = Double.random(in: configuration.listLatency)
            if latency > 0 { try await Task.sleep(nanoseconds: UInt64(latency * 1_000_000_000)) }
            return success(200, allRecords(for: user).map(\.loan).sorted { $0.createdAt > $1.createdAt })
        }
        if method == "POST", segments == ["loans", "quote"] { return quote(request) }
        if method == "POST", segments == ["loans"] { return createLoan(request, user: user) }
        if method == "GET", segments.count == 2, segments[0] == "loans" {
            guard let record = allRecords(for: user).first(where: { $0.loan.id == segments[1] }) else {
                return failure(404, code: "loan_not_found", message: "El préstamo no existe.")
            }
            return success(200, LoanDetail(loan: record.loan, schedule: record.schedule))
        }
        return failure(404, code: "route_not_found", message: "Ruta no encontrada.")
    }

    // MARK: Auth

    private func login(_ request: MockRequest) -> MockResponse {
        guard let body = try? JSONCoding.makeDecoder().decode(LoginRequest.self, from: request.body) else {
            return failure(400, code: "bad_request", message: "Cuerpo inválido.")
        }
        guard body.username == Self.demoUsername, body.password == Self.demoPassword else {
            return failure(401, code: "invalid_credentials", message: "Credenciales inválidas.")
        }
        return success(200, issueTokens(for: body.username))
    }

    private func refresh(_ request: MockRequest) -> MockResponse {
        guard let body = try? JSONCoding.makeDecoder().decode(RefreshRequest.self, from: request.body) else {
            return failure(400, code: "bad_request", message: "Cuerpo inválido.")
        }
        guard let claims = verify(body.refreshToken, kind: TokenKind.refresh), claims.expiresAt > now() else {
            return failure(401, code: "refresh_expired", message: "El refresh token expiró.")
        }
        return success(200, issueTokens(for: claims.subject))
    }

    private func issueTokens(for user: String) -> TokenPair {
        TokenPair(accessToken: makeToken(kind: TokenKind.access, subject: user,
                                         lifetime: configuration.accessTokenLifetime),
                  refreshToken: makeToken(kind: TokenKind.refresh, subject: user,
                                          lifetime: configuration.refreshTokenLifetime),
                  expiresIn: Int(configuration.accessTokenLifetime))
    }

    private func authenticatedUser(_ request: MockRequest) -> String? {
        guard let header = request.headers.first(where: { $0.key.lowercased() == "authorization" })?.value,
              header.hasPrefix("Bearer "),
              let claims = verify(String(header.dropFirst("Bearer ".count)), kind: TokenKind.access),
              claims.expiresAt > now()
        else { return nil }
        return claims.subject
    }

    private func makeToken(kind: String, subject: String, lifetime: TimeInterval) -> String {
        let claims = TokenClaims(kind: kind, subject: subject,
                                 expiresAt: now().addingTimeInterval(lifetime), id: UUID().uuidString)
        let payload = JSONCoding.encode(claims)
        let signature = Data(HMAC<SHA256>.authenticationCode(for: payload, using: signingKey))
        return "\(payload.base64URLEncoded()).\(signature.base64URLEncoded())"
    }

    private func verify(_ token: String, kind: String) -> TokenClaims? {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 2,
              let payload = Data(base64URLEncoded: parts[0]),
              let signature = Data(base64URLEncoded: parts[1]),
              HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: payload, using: signingKey),
              let claims = try? JSONCoding.makeDecoder().decode(TokenClaims.self, from: payload),
              claims.kind == kind
        else { return nil }
        return claims
    }

    // MARK: Loans

    private func quote(_ request: MockRequest) -> MockResponse {
        guard let terms = try? JSONCoding.makeDecoder().decode(LoanTerms.self, from: request.body) else {
            return failure(400, code: "bad_request", message: "Cuerpo inválido.")
        }
        if let invalid = validate(terms) { return invalid }
        return success(200, LoanCalculator.quote(for: terms))
    }

    private func createLoan(_ request: MockRequest, user: String) -> MockResponse {
        guard let key = request.headers.first(where: { $0.key.lowercased() == "idempotency-key" })?.value,
              !key.isEmpty
        else {
            return failure(400, code: "idempotency_key_required", message: "Falta el encabezado Idempotency-Key.")
        }
        // Repetir la llave devuelve el mismo préstamo, aunque el 500 aleatorio habría caído.
        if let loanID = snapshot.idempotency[key],
           let record = snapshot.created.first(where: { $0.loan.id == loanID && $0.owner == user }) {
            return success(201, record.loan)
        }
        guard let terms = try? JSONCoding.makeDecoder().decode(LoanTerms.self, from: request.body) else {
            return failure(400, code: "bad_request", message: "Cuerpo inválido.")
        }
        if let invalid = validate(terms) { return invalid }
        if random() < configuration.createFailureProbability {
            return failure(500, code: "internal_error", message: "Error interno. Intenta de nuevo.")
        }

        let createdAt = now()
        let schedule = LoanCalculator.schedule(
            for: terms,
            firstDueDate: Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: createdAt) ?? createdAt,
            paidCount: 0)
        let loan = Loan(id: "L-\(snapshot.nextID)", amountCents: terms.amountCents,
                        outstandingBalanceCents: terms.amountCents, termMonths: terms.termMonths,
                        annualRatePercent: LoanCalculator.annualRatePercent(termMonths: terms.termMonths),
                        nextPaymentDate: nil, status: .enRevision, createdAt: createdAt)
        snapshot.nextID += 1
        snapshot.created.append(Record(owner: user, loan: loan, schedule: schedule.installments))
        snapshot.idempotency[key] = loan.id
        persist()
        return success(201, loan)
    }

    private func validate(_ terms: LoanTerms) -> MockResponse? {
        var fields: [String: String] = [:]
        let amount = LoanApplicationRules.amountPesos
        if terms.amountCents < amount.lowerBound * 100 || terms.amountCents > amount.upperBound * 100 {
            fields["amountCents"] = "El monto debe estar entre 5,000 y 100,000 DOP."
        }
        let term = LoanApplicationRules.termMonths
        if !term.contains(terms.termMonths) {
            fields["termMonths"] = "El plazo debe estar entre 3 y 24 meses."
        }
        guard !fields.isEmpty else { return nil }
        let message = fields.sorted { $0.key < $1.key }.map(\.value).joined(separator: " ")
        return failure(422, code: "validation_error", message: message, fields: fields)
    }

    private func allRecords(for user: String) -> [Record] {
        (seeded + snapshot.created).filter { $0.owner == user }
    }

    private func persist() {
        persistence?.save(JSONCoding.encode(snapshot))
    }

    // MARK: Respuestas

    private func success<T: Encodable>(_ status: Int, _ value: T) -> MockResponse {
        MockResponse(status: status, body: JSONCoding.encode(value))
    }

    private func failure(_ status: Int, code: String, message: String, fields: [String: String]? = nil) -> MockResponse {
        let envelope = APIErrorEnvelope(error: .init(code: code, message: message, fields: fields))
        return MockResponse(status: status, body: JSONCoding.encode(envelope))
    }

    // MARK: Datos de ejemplo

    private static func makeSeedRecords(owner: String, now: Date) -> [Record] {
        let calendar = Calendar(identifier: .gregorian)
        func date(monthsFromNow months: Int, days: Int = 0) -> Date {
            let shifted = calendar.date(byAdding: .month, value: months, to: now) ?? now
            return calendar.date(byAdding: .day, value: days, to: shifted) ?? shifted
        }

        func record(id: String, pesos: Int, term: Int, status: LoanStatus, paid: Int,
                    firstDue: Date, createdAt: Date) -> Record {
            let terms = LoanTerms(amountCents: pesos * 100, termMonths: term)
            let schedule = LoanCalculator.schedule(for: terms, firstDueDate: firstDue, paidCount: paid)
            let disbursed = status == .desembolsado || status == .pagado
            let balance = status == .rechazado ? 0 : (disbursed ? schedule.balanceAfter[paid] : terms.amountCents)
            let nextDue = status == .desembolsado ? schedule.installments.first(where: { !$0.isPaid })?.dueDate : nil
            let loan = Loan(id: id, amountCents: terms.amountCents, outstandingBalanceCents: balance,
                            termMonths: term, annualRatePercent: LoanCalculator.annualRatePercent(termMonths: term),
                            nextPaymentDate: nextDue, status: status, createdAt: createdAt)
            return Record(owner: owner, loan: loan,
                          schedule: status == .rechazado ? [] : schedule.installments)
        }

        return [
            record(id: "L-1001", pesos: 50_000, term: 12, status: .desembolsado, paid: 4,
                   firstDue: date(monthsFromNow: -3, days: 5), createdAt: date(monthsFromNow: -5)),
            record(id: "L-1002", pesos: 20_000, term: 6, status: .enRevision, paid: 0,
                   firstDue: date(monthsFromNow: 1), createdAt: date(monthsFromNow: 0, days: -2)),
            record(id: "L-1003", pesos: 75_000, term: 18, status: .aprobado, paid: 0,
                   firstDue: date(monthsFromNow: 1), createdAt: date(monthsFromNow: 0, days: -6)),
            record(id: "L-1004", pesos: 100_000, term: 24, status: .rechazado, paid: 0,
                   firstDue: date(monthsFromNow: 1), createdAt: date(monthsFromNow: -2)),
            record(id: "L-1005", pesos: 10_000, term: 6, status: .pagado, paid: 6,
                   firstDue: date(monthsFromNow: -11), createdAt: date(monthsFromNow: -12))
        ]
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
