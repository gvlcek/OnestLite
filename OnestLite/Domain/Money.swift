import Foundation

enum Money {
    static let locale = Locale(identifier: "es_DO")

    /// Formatea centavos como pesos dominicanos con formato local, p. ej. `RD$25,000.00`.
    static func format(cents: Int) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: "DOP").locale(locale))
    }

    static func format(pesos: Int) -> String {
        format(cents: pesos * 100)
    }
}

enum DisplayDate {
    static func string(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Money.locale))
    }
}
