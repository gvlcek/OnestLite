import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel: LoginViewModel
    private let notice: String?
    @FocusState private var focus: Field?

    private enum Field { case username, password }

    init(auth: AuthRepository, notice: String?, onSuccess: @escaping @MainActor () -> Void) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(auth: auth, onSuccess: onSuccess))
        self.notice = notice
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("Onest Lite")
                        .font(.largeTitle.bold())
                    Text("Consulta y solicita tus préstamos")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                if let message = viewModel.errorMessage ?? notice {
                    MessageBanner(text: message, style: .error)
                }

                VStack(spacing: 12) {
                    TextField("Usuario", text: $viewModel.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                        .textFieldStyle(.roundedBorder)

                    SecureField("Contraseña", text: $viewModel.password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await viewModel.submit() } }
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    Task { await viewModel.submit() }
                } label: {
                    HStack {
                        if viewModel.isLoading { ProgressView().tint(.white) }
                        Text("Iniciar sesión")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canSubmit)

                Text("Demo: usuario \(MockBackend.demoUsername) · contraseña \(MockBackend.demoPassword)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
