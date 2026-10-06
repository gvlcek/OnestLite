import Foundation

@MainActor
final class LoansViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded([Loan])
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Error de un refresh cuando ya hay datos en pantalla: se muestra como aviso sin borrar la lista.
    @Published private(set) var refreshError: String?

    private let repository: LoanRepository

    init(repository: LoanRepository) {
        self.repository = repository
    }

    /// Carga inicial. No hace nada si ya hay datos (la vista puede reaparecer).
    func load() async {
        switch state {
        case .idle, .failed:
            state = .loading
            await fetch()
        case .loading, .loaded:
            break
        }
    }

    /// Pull to refresh y recarga tras crear un préstamo: conserva la lista mientras actualiza.
    func refresh() async {
        if case .loaded = state {
            await fetch()
        } else {
            state = .loading
            await fetch()
        }
    }

    private func fetch() async {
        do {
            let loans = try await repository.loans()
            state = .loaded(loans)
            refreshError = nil
        } catch {
            guard let message = error.userFacingMessage else {
                // Cancelado (p. ej. la vista desapareció): si estábamos cargando, volvemos a idle.
                if case .loading = state { state = .idle }
                return
            }
            if case .loaded = state {
                refreshError = message
            } else {
                state = .failed(message)
            }
        }
    }
}
