import SwiftUI

struct LoanDetailView: View {
    @StateObject private var viewModel: LoanDetailViewModel

    init(loan: Loan, repository: LoanRepository) {
        _viewModel = StateObject(wrappedValue: LoanDetailViewModel(loan: loan, repository: repository))
    }

    var body: some View {
        List {
            summarySection
            switch viewModel.state {
            case .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case .failed(let message):
                Section {
                    MessageBanner(text: message)
                    Button("Reintentar") { Task { await viewModel.load() } }
                }
            case .loaded(let detail):
                scheduleSection(detail.schedule)
            }
        }
        .navigationTitle("Préstamo \(viewModel.loan.id)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private var summarySection: some View {
        let loan = viewModel.loan
        return Section("Resumen") {
            HStack {
                Text(Money.format(cents: loan.amountCents)).font(.title2.bold())
                Spacer()
                StatusBadge(status: loan.status)
            }
            LabeledValue(label: "Saldo pendiente", value: Money.format(cents: loan.outstandingBalanceCents))
            LabeledValue(label: "Plazo", value: "\(loan.termMonths) meses")
            LabeledValue(label: "Tasa anual", value: String(format: "%.1f %%", loan.annualRatePercent))
            LabeledValue(label: "Próximo pago", value: loan.nextPaymentDate.map(DisplayDate.string) ?? "—")
        }
    }

    @ViewBuilder
    private func scheduleSection(_ schedule: [Installment]) -> some View {
        Section("Calendario de pagos") {
            if schedule.isEmpty {
                Text("Este préstamo no tiene calendario de pagos.")
                    .foregroundStyle(.secondary)
            }
            ForEach(schedule) { installment in
                HStack {
                    Image(systemName: installment.isPaid ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(installment.isPaid ? Color.green : Color.secondary)
                        .accessibilityLabel(installment.isPaid ? "Pagada" : "Pendiente")
                    VStack(alignment: .leading) {
                        Text("Cuota \(installment.number)")
                        Text(DisplayDate.string(installment.dueDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Money.format(cents: installment.amountCents))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
