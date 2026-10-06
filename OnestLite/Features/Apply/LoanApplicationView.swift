import SwiftUI

struct LoanApplicationView: View {
    @StateObject private var viewModel: LoanApplicationViewModel
    private let onFinish: () -> Void

    init(repository: LoanRepository, onFinish: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: LoanApplicationViewModel(repository: repository))
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .terms: TermsStep(viewModel: viewModel)
                case .summary: SummaryStep(viewModel: viewModel)
                case .confirmation: ConfirmationStep(viewModel: viewModel, onFinish: onFinish)
                }
            }
            .navigationTitle("Solicitar préstamo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.step != .confirmation {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancelar") { onFinish() }
                    }
                }
                ToolbarItem(placement: .principal) {
                    StepIndicator(step: viewModel.step)
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isLoading)
    }
}

private struct StepIndicator: View {
    let step: LoanApplicationViewModel.Step

    var body: some View {
        let index: Int = switch step {
        case .terms: 1
        case .summary: 2
        case .confirmation: 3
        }
        Text("Paso \(index) de 3")
            .font(.subheadline.weight(.semibold))
    }
}

private struct TermsStep: View {
    @ObservedObject var viewModel: LoanApplicationViewModel
    @FocusState private var amountFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Monto en DOP", text: $viewModel.amountText)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .onChange(of: viewModel.amountText) { _ in viewModel.amountDidChange() }
                if let message = viewModel.amountErrorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("¿Cuánto necesitas?")
            } footer: {
                let range = LoanApplicationRules.amountPesos
                Text("Entre \(Money.format(pesos: range.lowerBound)) y \(Money.format(pesos: range.upperBound)).")
            }

            Section("Plazo") {
                Stepper(value: $viewModel.termMonths, in: LoanApplicationRules.termMonths) {
                    Text("\(viewModel.termMonths) meses")
                }
            }

            if let message = viewModel.errorMessage {
                Section { MessageBanner(text: message) }
            }

            Section {
                Button {
                    amountFocused = false
                    Task { await viewModel.requestQuote() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isLoading { ProgressView() } else { Text("Continuar") }
                        Spacer()
                    }
                }
                .disabled(!viewModel.canRequestQuote)
            }
        }
    }
}

private struct SummaryStep: View {
    @ObservedObject var viewModel: LoanApplicationViewModel

    var body: some View {
        Form {
            if let quote = viewModel.quote {
                Section("Condiciones") {
                    LabeledValue(label: "Monto", value: Money.format(cents: quote.amountCents))
                    LabeledValue(label: "Plazo", value: "\(quote.termMonths) meses")
                    LabeledValue(label: "Tasa anual", value: String(format: "%.1f %%", quote.annualRatePercent))
                    LabeledValue(label: "Cuota mensual", value: Money.format(cents: quote.monthlyPaymentCents))
                    LabeledValue(label: "Costo total", value: Money.format(cents: quote.totalCostCents))
                }
            }

            if let message = viewModel.errorMessage {
                Section {
                    MessageBanner(text: message)
                    Text("Si vuelves a intentar, tu solicitud no se duplicará.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await viewModel.submit() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isLoading { ProgressView() } else { Text("Confirmar solicitud") }
                        Spacer()
                    }
                }
                .disabled(viewModel.isLoading)

                Button("Editar condiciones") { viewModel.editTerms() }
                    .disabled(viewModel.isLoading)
            }
        }
    }
}

private struct ConfirmationStep: View {
    @ObservedObject var viewModel: LoanApplicationViewModel
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("¡Solicitud enviada!")
                .font(.title2.bold())
            if let loan = viewModel.createdLoan {
                VStack(spacing: 8) {
                    Text("Tu préstamo \(loan.id) por \(Money.format(cents: loan.amountCents)) está")
                    StatusBadge(status: loan.status)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Listo") { onFinish() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(24)
    }
}
