import XCTest
@testable import OnestLite

final class LoanApplicationValidatorTests: XCTestCase {
    func testValidInputProducesTerms() {
        let result = LoanApplicationValidator.validate(amountText: "25000", termMonths: 12)
        XCTAssertEqual(result.terms, LoanTerms(amountCents: 2_500_000, termMonths: 12))
        XCTAssertTrue(result.isValid)
    }

    func testBoundariesAreInclusive() {
        XCTAssertTrue(LoanApplicationValidator.validate(amountText: "5000", termMonths: 3).isValid)
        XCTAssertTrue(LoanApplicationValidator.validate(amountText: "100000", termMonths: 24).isValid)
    }

    func testAmountOutsideRange() {
        XCTAssertEqual(LoanApplicationValidator.validate(amountText: "4999.99", termMonths: 12).amountIssue, .outOfRange)
        XCTAssertEqual(LoanApplicationValidator.validate(amountText: "100000.01", termMonths: 12).amountIssue, .outOfRange)
        XCTAssertNil(LoanApplicationValidator.validate(amountText: "4999.99", termMonths: 12).terms)
    }

    func testTermOutsideRange() {
        XCTAssertEqual(LoanApplicationValidator.validate(amountText: "10000", termMonths: 2).termIssue, .outOfRange)
        XCTAssertEqual(LoanApplicationValidator.validate(amountText: "10000", termMonths: 25).termIssue, .outOfRange)
    }

    func testEmptyAndGarbageAmounts() {
        XCTAssertEqual(LoanApplicationValidator.validate(amountText: "", termMonths: 12).amountIssue, .empty)
        XCTAssertEqual(LoanApplicationValidator.validate(amountText: "   ", termMonths: 12).amountIssue, .empty)
        for garbage in ["abc", "12a", "1.2.3", "-5000", ".5", "5000.123", "1e5", "٥٠٠٠"] {
            XCTAssertEqual(LoanApplicationValidator.validate(amountText: garbage, termMonths: 12).amountIssue,
                           .notANumber, "\(garbage) debería ser inválido")
        }
    }

    func testParsingAcceptsLocalFormatting() {
        XCTAssertEqual(LoanApplicationValidator.parseAmountCents("25,000"), 2_500_000)
        XCTAssertEqual(LoanApplicationValidator.parseAmountCents("RD$ 25,000.50"), 2_500_050)
        XCTAssertEqual(LoanApplicationValidator.parseAmountCents("25000.5"), 2_500_050)
        XCTAssertEqual(LoanApplicationValidator.parseAmountCents("25000."), 2_500_000)
    }

    func testParsingHasNoFloatingPointDrift() {
        XCTAssertEqual(LoanApplicationValidator.parseAmountCents("19999.99"), 1_999_999)
        XCTAssertEqual(LoanApplicationValidator.parseAmountCents("0.07"), 7)
    }

    func testHugeNumbersDoNotOverflow() {
        XCTAssertNil(LoanApplicationValidator.parseAmountCents("99999999999999999999"))
    }

    func testMoneyFormatUsesDominicanPesos() {
        let formatted = Money.format(cents: 2_500_000)
        XCTAssertTrue(formatted.contains("RD$"), formatted)
        XCTAssertTrue(formatted.contains("25,000.00"), formatted)
    }
}
