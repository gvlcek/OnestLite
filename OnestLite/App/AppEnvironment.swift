import Foundation

/// Composition root: aquí se decide qué transporte usa la app.
@MainActor
final class AppEnvironment: ObservableObject {
    let session: AppSession
    let auth: AuthRepository
    let loans: LoanRepository

    init(session: AppSession, auth: AuthRepository, loans: LoanRepository) {
        self.session = session
        self.auth = auth
        self.loans = loans
    }

    /// Variables de entorno opcionales (Edit Scheme > Run > Arguments) para probar escenarios:
    /// - `ONEST_ACCESS_LIFETIME`  vida del access token en segundos (60 por defecto)
    /// - `ONEST_REFRESH_LIFETIME` vida del refresh token en segundos (600 por defecto)
    /// - `ONEST_FAST_MOCK=1`      sin latencia artificial en GET /loans
    static func live(processInfo: ProcessInfo = .processInfo, defaults: UserDefaults = .standard) -> AppEnvironment {
        let baseURL = URL(string: "https://api.onest-lite.mock")!
        let store = KeychainTokenStore(service: "com.onest.OnestLite.session")

        // Keychain sobrevive a la desinstalación; en la primera ejecución partimos de cero.
        let launchedKey = "onest.hasLaunchedBefore"
        if !defaults.bool(forKey: launchedKey) {
            try? store.clear()
            defaults.set(true, forKey: launchedKey)
        }

        var configuration = MockBackend.Configuration()
        let env = processInfo.environment
        if env["ONEST_FAST_MOCK"] == "1" { configuration.listLatency = 0...0 }
        if let value = env["ONEST_ACCESS_LIFETIME"].flatMap(TimeInterval.init) { configuration.accessTokenLifetime = value }
        if let value = env["ONEST_REFRESH_LIFETIME"].flatMap(TimeInterval.init) { configuration.refreshTokenLifetime = value }
        let backend = MockBackend(configuration: configuration, persistence: filePersistence())
        let transport = MockTransport(backend: backend)
        // Backend real: `URLSessionTransport()` y la baseURL del servidor.

        let auth = AuthSession(baseURL: baseURL, transport: transport, store: store)
        let client = APIClient(baseURL: baseURL, transport: transport, auth: auth)
        return AppEnvironment(session: AppSession(auth: auth),
                              auth: auth,
                              loans: APILoanRepository(client: client))
    }

    private static func filePersistence() -> MockBackend.Persistence? {
        guard let directory = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                           appropriateFor: nil, create: true)
        else { return nil }
        let url = directory.appendingPathComponent("onest-mock-state.json")
        return MockBackend.Persistence(
            load: { try? Data(contentsOf: url) },
            save: { try? $0.write(to: url, options: .atomic) })
    }
}
