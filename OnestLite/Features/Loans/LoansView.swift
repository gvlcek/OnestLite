import SwiftUI

struct LoansView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel: LoansViewModel
    private let repository: LoanRepository
    @State private var showsApplication = false
    @State private var confirmsLogout = false

    init(repository: LoanRepository) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: LoansViewModel(repository: repository))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Mis préstamos")
                .navigationDestination(for: Loan.self) { loan in
                    LoanDetailView(loan: loan, repository: repository)
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Salir") { confirmsLogout = true }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showsApplication = true
                        } label: {
                            Label("Solicitar préstamo", systemImage: "plus")
                        }
                    }
                }
                .confirmationDialog("¿Cerrar sesión?", isPresented: $confirmsLogout, titleVisibility: .visible) {
                    Button("Cerrar sesión", role: .destructive) {
                        Task { await session.logout() }
                    }
                } message: {
                    Text("Se eliminarán las credenciales guardadas en este dispositivo.")
                }
                .sheet(isPresented: $showsApplication) {
                    LoanApplicationView(repository: repository) {
                        showsApplication = false
                        Task { await viewModel.refresh() }
                    }
                }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Cargando préstamos…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 16) {
                MessageBanner(text: message)
                Button("Reintentar") { Task { await viewModel.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxHeight: .infinity)
        case .loaded(let loans):
            List {
                if let error = viewModel.refreshError {
                    MessageBanner(text: error)
                        .listRowSeparator(.hidden)
                }
                if loans.isEmpty {
                    Text("Todavía no tienes préstamos. Toca + para solicitar uno.")
                        .foregroundStyle(.secondary)
                }
                ForEach(loans) { loan in
                    NavigationLink(value: loan) {
                        LoanRow(loan: loan)
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await viewModel.refresh() }
        }
    }
}

private struct LoanRow: View {
    let loan: Loan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Money.format(cents: loan.amountCents))
                    .font(.headline)
                Spacer()
                StatusBadge(status: loan.status)
            }
            LabeledValue(label: "Saldo pendiente", value: Money.format(cents: loan.outstandingBalanceCents))
                .font(.subheadline)
            LabeledValue(label: "Próximo pago",
                         value: loan.nextPaymentDate.map(DisplayDate.string) ?? "—")
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}
