import Foundation

enum LoanApplicationRules {
    static let amountPesos: ClosedRange<Int> = 5_000...100_000
    static let termMonths: ClosedRange<Int> = 3...24
}

struct LoanApplicationValidation: Equatable {
    enum AmountIssue: Equatable {
        case empty
        case notANumber
        case outOfRange
    }

    enum TermIssue: Equatable {
        case outOfRange
    }

    /// Solo presente cuando monto y plazo son válidos.
    let terms: LoanTerms?
    let amountIssue: AmountIssue?
    let termIssue: TermIssue?

    var isValid: Bool { terms != nil }
}

enum LoanApplicationValidator {
    static func validate(amountText: String, termMonths: Int) -> LoanApplicationValidation {
        var amountIssue: LoanApplicationValidation.AmountIssue?
        var amountCents: Int?

        if amountText.trimmingCharacters(in: .whitespaces).isEmpty {
            amountIssue = .empty
        } else if let cents = parseAmountCents(amountText) {
            let range = LoanApplicationRules.amountPesos
            if cents < range.lowerBound * 100 || cents > range.upperBound * 100 {
                amountIssue = .outOfRange
            } else {
                amountCents = cents
            }
        } else {
            amountIssue = .notANumber
        }

        let termIssue: LoanApplicationValidation.TermIssue? =
            LoanApplicationRules.termMonths.contains(termMonths) ? nil : .outOfRange

        let terms: LoanTerms? = {
            guard let amountCents, termIssue == nil else { return nil }
            return LoanTerms(amountCents: amountCents, termMonths: termMonths)
        }()
        return LoanApplicationValidation(terms: terms, amountIssue: amountIssue, termIssue: termIssue)
    }

    /// Convierte "25,000", "RD$ 25000.50" o "25000" a centavos sin pasar por `Double`.
    /// Acepta coma como separador de miles y punto como decimal (formato es_DO). Máximo 2 decimales.
    static func parseAmountCents(_ text: String) -> Int? {
        var cleaned = text.uppercased().replacingOccurrences(of: "RD$", with: "")
        cleaned = cleaned.filter { !$0.isWhitespace && $0 != "," && $0 != "$" }
        guard !cleaned.isEmpty else { return nil }

        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }

        let whole = parts[0]
        let fraction = parts.count == 2 ? parts[1] : ""
        guard !whole.isEmpty, whole.count <= 9, whole.allSatisfy(\.isASCIIDigit),
              fraction.count <= 2, fraction.allSatisfy(\.isASCIIDigit),
              let wholeValue = Int(whole)
        else { return nil }

        let fractionValue = Int(fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        return wholeValue * 100 + fractionValue
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
