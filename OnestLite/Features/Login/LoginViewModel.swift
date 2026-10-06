import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var username = ""
    @Published var password = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let auth: AuthRepository
    private let onSuccess: @MainActor () -> Void

    init(auth: AuthRepository, onSuccess: @escaping @MainActor () -> Void) {
        self.auth = auth
        self.onSuccess = onSuccess
    }

    var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isLoading
    }

    func submit() async {
        guard canSubmit else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await auth.login(username: username.trimmingCharacters(in: .whitespaces), password: password)
            password = ""
            onSuccess()
        } catch {
            password = ""
            errorMessage = error.userFacingMessage
        }
    }
}
