import Foundation

/// Estado global de sesión que decide qué pantalla raíz se muestra.
@MainActor
final class AppSession: ObservableObject {
    enum Phase: Equatable {
        case launching
        case loggedOut
        case loggedIn
    }

    @Published private(set) var phase: Phase = .launching
    /// Aviso mostrado en el login cuando la sesión se cerró sola (refresh token vencido).
    @Published private(set) var notice: String?
    /// Cambia en cada login/logout: la vista raíz lo usa como `id` para descartar todo el estado de UI.
    @Published private(set) var generation = 0

    private let auth: AuthRepository
    private var expirationTask: Task<Void, Never>?

    init(auth: AuthRepository) {
        self.auth = auth
    }

    deinit {
        expirationTask?.cancel()
    }

    func start() async {
        guard expirationTask == nil else { return }
        let expirations = auth.sessionExpirations
        expirationTask = Task { [weak self] in
            for await _ in expirations {
                self?.sessionDidExpire()
            }
        }
        phase = await auth.hasSession() ? .loggedIn : .loggedOut
    }

    func didLogin() {
        notice = nil
        generation += 1
        phase = .loggedIn
    }

    func logout() async {
        await auth.logout()
        notice = nil
        generation += 1
        phase = .loggedOut
    }

    private func sessionDidExpire() {
        guard phase == .loggedIn else { return }
        notice = "Tu sesión expiró. Inicia sesión de nuevo."
        generation += 1
        phase = .loggedOut
    }
}
