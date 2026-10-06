import Foundation

/// Flujo de solicitud en tres pasos: condiciones → resumen → confirmación.
@MainActor
final class LoanApplicationViewModel: ObservableObject {
    enum Step: Equatable {
        case terms
        case summary
        case confirmation
    }

    @Published var amountText = ""
    @Published var termMonths = 12
    @Published private(set) var step: Step = .terms
    @Published private(set) var quote: LoanQuote?
    @Published private(set) var createdLoan: Loan?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// Los errores de validación solo se muestran después del primer intento de continuar o al editar.
    @Published private(set) var showsValidation = false

    private let repository: LoanRepository
    private let makeIdempotencyKey: () -> String
    /// Identifica esta solicitud. Se crea una vez y se reusa en cada reintento del mismo envío;
    /// si el usuario vuelve y cambia las condiciones, es otra solicitud y se genera otra llave.
    private var idempotencyKey: String?

    init(repository: LoanRepository, makeIdempotencyKey: @escaping () -> String = { UUID().uuidString }) {
        self.repository = repository
        self.makeIdempotencyKey = makeIdempotencyKey
    }

    var validation: LoanApplicationValidation {
        LoanApplicationValidator.validate(amountText: amountText, termMonths: termMonths)
    }

    var amountErrorMessage: String? {
        guard showsValidation || !amountText.isEmpty else { return nil }
        switch validation.amountIssue {
        case .none: return nil
        case .empty: return showsValidation ? "Ingresa el monto que necesitas." : nil
        case .notANumber: return "Ingresa un monto válido, por ejemplo 25000."
        case .outOfRange:
            let range = LoanApplicationRules.amountPesos
            return "El monto debe estar entre \(Money.format(pesos: range.lowerBound)) y \(Money.format(pesos: range.upperBound))."
        }
    }

    var canRequestQuote: Bool { validation.isValid && !isLoading }

    func amountDidChange() {
        errorMessage = nil
    }

    func requestQuote() async {
        showsValidation = true
        guard let terms = validation.terms, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            quote = try await repository.quote(terms)
            step = .summary
        } catch {
            errorMessage = error.userFacingMessage
        }
    }

    func submit() async {
        guard step == .summary, let terms = quoteTerms, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let key = idempotencyKey ?? makeIdempotencyKey()
        idempotencyKey = key
        do {
            createdLoan = try await repository.create(terms, idempotencyKey: key)
            step = .confirmation
        } catch {
            // Se conserva la llave: si el servidor sí procesó la solicitud, reintentar devuelve el mismo préstamo.
            errorMessage = error.userFacingMessage
        }
    }

    func editTerms() {
        guard step == .summary else { return }
        step = .terms
        quote = nil
        errorMessage = nil
        idempotencyKey = nil
    }

    private var quoteTerms: LoanTerms? {
        quote.map { LoanTerms(amountCents: $0.amountCents, termMonths: $0.termMonths) }
    }
}
