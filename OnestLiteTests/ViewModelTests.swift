import XCTest
@testable import OnestLite

@MainActor
final class LoansViewModelTests: XCTestCase {
    func testLoadPublishesLoans() async {
        let repository = FakeLoanRepository()
        repository.enqueueLoans(.success([Fixtures.loan()]))
        let viewModel = LoansViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded([Fixtures.loan()]))
    }

    func testInitialFailureShowsErrorAndRetryRecovers() async {
        let repository = FakeLoanRepository()
        repository.enqueueLoans(.failure(APIError.network))
        repository.enqueueLoans(.success([Fixtures.loan()]))
        let viewModel = LoansViewModel(repository: repository)

        await viewModel.load()
        XCTAssertEqual(viewModel.state, .failed(APIError.network.userMessage))

        await viewModel.load()
        XCTAssertEqual(viewModel.state, .loaded([Fixtures.loan()]))
    }

    func testFailedRefreshKeepsExistingLoansAndShowsWarning() async {
        let repository = FakeLoanRepository()
        repository.enqueueLoans(.success([Fixtures.loan()]))
        repository.enqueueLoans(.failure(APIError.server(status: 500)))
        let viewModel = LoansViewModel(repository: repository)

        await viewModel.load()
        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded([Fixtures.loan()]))
        XCTAssertEqual(viewModel.refreshError, APIError.server(status: 500).userMessage)
    }

    func testSuccessfulRefreshClearsWarning() async {
        let repository = FakeLoanRepository()
        repository.enqueueLoans(.success([Fixtures.loan()]))
        repository.enqueueLoans(.failure(APIError.network))
        repository.enqueueLoans(.success([Fixtures.loan(id: "L-2")]))
        let viewModel = LoansViewModel(repository: repository)

        await viewModel.load()
        await viewModel.refresh()
        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded([Fixtures.loan(id: "L-2")]))
        XCTAssertNil(viewModel.refreshError)
    }
}

@MainActor
final class LoanApplicationViewModelTests: XCTestCase {
    private func makeViewModel(_ repository: FakeLoanRepository, keys: [String] = ["key-1", "key-2"]) -> LoanApplicationViewModel {
        var remaining = keys
        return LoanApplicationViewModel(repository: repository, makeIdempotencyKey: { remaining.removeFirst() })
    }

    func testCannotRequestQuoteWithInvalidAmount() async {
        let repository = FakeLoanRepository()
        let viewModel = makeViewModel(repository)
        viewModel.amountText = "100"

        XCTAssertFalse(viewModel.canRequestQuote)
        await viewModel.requestQuote()

        XCTAssertEqual(viewModel.step, .terms)
        XCTAssertNotNil(viewModel.amountErrorMessage)
    }

    func testHappyPathAdvancesThroughThreeSteps() async {
        let repository = FakeLoanRepository()
        repository.setQuote(.success(Fixtures.quote))
        repository.enqueueCreate(.success(Fixtures.loan()))
        let viewModel = makeViewModel(repository)
        viewModel.amountText = "25000"

        await viewModel.requestQuote()
        XCTAssertEqual(viewModel.step, .summary)
        XCTAssertEqual(viewModel.quote, Fixtures.quote)

        await viewModel.submit()
        XCTAssertEqual(viewModel.step, .confirmation)
        XCTAssertEqual(viewModel.createdLoan, Fixtures.loan())
    }

    func testRetryAfterServerErrorReusesTheSameIdempotencyKey() async {
        let repository = FakeLoanRepository()
        repository.setQuote(.success(Fixtures.quote))
        repository.enqueueCreate(.failure(APIError.server(status: 500)))
        repository.enqueueCreate(.success(Fixtures.loan()))
        let viewModel = makeViewModel(repository)
        viewModel.amountText = "25000"
        await viewModel.requestQuote()

        await viewModel.submit()
        XCTAssertEqual(viewModel.step, .summary)
        XCTAssertEqual(viewModel.errorMessage, APIError.server(status: 500).userMessage)

        await viewModel.submit()
        XCTAssertEqual(viewModel.step, .confirmation)
        XCTAssertEqual(repository.createdKeys, ["key-1", "key-1"])
    }

    func testEditingTermsStartsANewRequestWithANewKey() async {
        let repository = FakeLoanRepository()
        repository.setQuote(.success(Fixtures.quote))
        repository.enqueueCreate(.failure(APIError.network))
        repository.enqueueCreate(.success(Fixtures.loan()))
        let viewModel = makeViewModel(repository)
        viewModel.amountText = "25000"
        await viewModel.requestQuote()
        await viewModel.submit()

        viewModel.editTerms()
        XCTAssertEqual(viewModel.step, .terms)
        viewModel.amountText = "30000"
        await viewModel.requestQuote()
        await viewModel.submit()

        XCTAssertEqual(repository.createdKeys, ["key-1", "key-2"])
    }

    func testServerValidationErrorIsShownOnTermsStep() async {
        let repository = FakeLoanRepository()
        repository.setQuote(.failure(APIError.validation(message: "Monto fuera de rango", fields: [:])))
        let viewModel = makeViewModel(repository)
        viewModel.amountText = "25000"

        await viewModel.requestQuote()

        XCTAssertEqual(viewModel.step, .terms)
        XCTAssertEqual(viewModel.errorMessage, "Monto fuera de rango")
    }
}

@MainActor
final class LoginViewModelTests: XCTestCase {
    private final class FakeAuth: AuthRepository, @unchecked Sendable {
        var error: Error?
        let sessionExpirations = AsyncStream<Void> { _ in }
        func login(username: String, password: String) async throws { if let error { throw error } }
        func logout() async {}
        func hasSession() async -> Bool { false }
    }

    func testSubmitIsDisabledUntilBothFieldsAreFilled() {
        let viewModel = LoginViewModel(auth: FakeAuth(), onSuccess: {})
        XCTAssertFalse(viewModel.canSubmit)
        viewModel.username = "demo"
        XCTAssertFalse(viewModel.canSubmit)
        viewModel.password = "x"
        XCTAssertTrue(viewModel.canSubmit)
    }

    func testSuccessfulLoginNotifiesAndClearsPassword() async {
        var succeeded = false
        let viewModel = LoginViewModel(auth: FakeAuth(), onSuccess: { succeeded = true })
        viewModel.username = "demo"
        viewModel.password = "secret"

        await viewModel.submit()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(viewModel.password, "")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testInvalidCredentialsShowsMessageAndClearsPassword() async {
        let auth = FakeAuth()
        auth.error = APIError.invalidCredentials
        var succeeded = false
        let viewModel = LoginViewModel(auth: auth, onSuccess: { succeeded = true })
        viewModel.username = "demo"
        viewModel.password = "wrong"

        await viewModel.submit()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(viewModel.errorMessage, APIError.invalidCredentials.userMessage)
        XCTAssertEqual(viewModel.password, "")
    }
}
