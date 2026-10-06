import Foundation

/// Montos siempre en centavos de DOP (`Int`) para evitar errores de punto flotante con dinero.

enum LoanStatus: String, Codable, CaseIterable, Sendable {
    case enRevision = "EN_REVISION"
    case aprobado = "APROBADO"
    case desembolsado = "DESEMBOLSADO"
    case rechazado = "RECHAZADO"
    case pagado = "PAGADO"

    var displayName: String {
        switch self {
        case .enRevision: return "En revisión"
        case .aprobado: return "Aprobado"
        case .desembolsado: return "Desembolsado"
        case .rechazado: return "Rechazado"
        case .pagado: return "Pagado"
        }
    }
}

struct Loan: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let amountCents: Int
    let outstandingBalanceCents: Int
    let termMonths: Int
    let annualRatePercent: Double
    let nextPaymentDate: Date?
    let status: LoanStatus
    let createdAt: Date
}

struct Installment: Codable, Identifiable, Equatable, Sendable {
    let number: Int
    let dueDate: Date
    let amountCents: Int
    let isPaid: Bool

    var id: Int { number }
}

struct LoanDetail: Codable, Equatable, Sendable {
    let loan: Loan
    let schedule: [Installment]
}

/// Condiciones pedidas por el usuario; se usa como cuerpo de `/loans/quote` y `/loans`.
struct LoanTerms: Codable, Equatable, Sendable {
    let amountCents: Int
    let termMonths: Int
}

struct LoanQuote: Codable, Equatable, Sendable {
    let amountCents: Int
    let termMonths: Int
    let monthlyPaymentCents: Int
    let annualRatePercent: Double
    let totalCostCents: Int
}

// MARK: - Auth

struct LoginRequest: Codable, Sendable {
    let username: String
    let password: String
}

struct RefreshRequest: Codable, Sendable {
    let refreshToken: String
}

struct TokenPair: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    /// Vida del access token en segundos.
    let expiresIn: Int
}

/// Lo que se guarda en Keychain.
struct StoredSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: Date
}

// MARK: - Errores del servidor

struct APIErrorEnvelope: Codable, Sendable {
    struct Body: Codable, Sendable {
        let code: String
        let message: String
        let fields: [String: String]?
    }

    let error: Body
}
