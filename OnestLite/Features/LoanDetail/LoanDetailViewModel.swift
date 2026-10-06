import Foundation

@MainActor
final class LoanDetailViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(LoanDetail)
        case failed(String)
    }

    @Published private(set) var state: State = .loading

    let loan: Loan
    private let repository: LoanRepository

    init(loan: Loan, repository: LoanRepository) {
        self.loan = loan
        self.repository = repository
    }

    func load() async {
        if case .loaded = state { return }
        state = .loading
        do {
            state = .loaded(try await repository.loan(id: loan.id))
        } catch {
            if let message = error.userFacingMessage {
                state = .failed(message)
            }
        }
    }
}
