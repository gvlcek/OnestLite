import Foundation

/// Cálculo de cuota y calendario (sistema francés: cuota fija). Vive en `Mock/` porque en un
/// backend real lo calcularía el servidor; la app solo muestra lo que recibe.
enum LoanCalculator {
    static func annualRatePercent(termMonths: Int) -> Double {
        switch termMonths {
        case ...6: return 22.0
        case ...12: return 24.0
        case ...18: return 26.0
        default: return 28.0
        }
    }

    static func monthlyPaymentCents(amountCents: Int, termMonths: Int, annualRatePercent: Double) -> Int {
        let monthlyRate = annualRatePercent / 100 / 12
        let principal = Double(amountCents)
        let months = Double(termMonths)
        let payment = monthlyRate == 0
            ? principal / months
            : principal * monthlyRate / (1 - pow(1 + monthlyRate, -months))
        return Int(payment.rounded())
    }

    static func quote(for terms: LoanTerms) -> LoanQuote {
        let rate = annualRatePercent(termMonths: terms.termMonths)
        let payment = monthlyPaymentCents(amountCents: terms.amountCents, termMonths: terms.termMonths,
                                          annualRatePercent: rate)
        return LoanQuote(amountCents: terms.amountCents, termMonths: terms.termMonths,
                         monthlyPaymentCents: payment, annualRatePercent: rate,
                         totalCostCents: payment * terms.termMonths)
    }

    struct Schedule {
        let installments: [Installment]
        /// `balanceAfter[k]` = capital pendiente tras pagar `k` cuotas (0...n).
        let balanceAfter: [Int]
    }

    static func schedule(for terms: LoanTerms, firstDueDate: Date, paidCount: Int,
                         calendar: Calendar = Calendar(identifier: .gregorian)) -> Schedule {
        let rate = annualRatePercent(termMonths: terms.termMonths)
        let payment = monthlyPaymentCents(amountCents: terms.amountCents, termMonths: terms.termMonths,
                                          annualRatePercent: rate)
        let monthlyRate = rate / 100 / 12

        var balance = Double(terms.amountCents)
        var balances = [terms.amountCents]
        var installments: [Installment] = []
        for index in 0..<terms.termMonths {
            let interest = balance * monthlyRate
            balance = index == terms.termMonths - 1 ? 0 : max(0, balance - (Double(payment) - interest))
            balances.append(Int(balance.rounded()))
            installments.append(Installment(
                number: index + 1,
                dueDate: calendar.date(byAdding: .month, value: index, to: firstDueDate) ?? firstDueDate,
                amountCents: payment,
                isPaid: index < paidCount))
        }
        return Schedule(installments: installments, balanceAfter: balances)
    }
}
