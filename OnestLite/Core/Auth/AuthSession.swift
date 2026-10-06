import Foundation

protocol AuthRepository: Sendable {
    func login(username: String, password: String) async throws
    func logout() async
    func hasSession() async -> Bool
    /// Emite cuando la sesión deja de ser recuperable y hay que volver al login.
    var sessionExpirations: AsyncStream<Void> { get }
}

/// Dueño de las credenciales. Al ser un `actor`, el estado de renovación está serializado:
/// si N peticiones reciben 401 a la vez, solo una llama a `/auth/refresh` y las demás esperan
/// su resultado. Es imprescindible con refresh tokens rotativos: reusar uno invalida la sesión.
actor AuthSession: AuthRepository {
    /// Margen para renovar antes de que el token expire de verdad.
    static let expiryLeeway: TimeInterval = 5

    nonisolated let sessionExpirations: AsyncStream<Void>
    private let expirationContinuation: AsyncStream<Void>.Continuation

    private let baseURL: URL
    private let transport: HTTPTransport
    private let store: TokenStore
    private let now: @Sendable () -> Date
    private var refreshTask: Task<StoredSession, Error>?
    /// Cambia en cada logout/expiración para que una renovación en vuelo no reescriba
    /// credenciales que el usuario ya borró.
    private var epoch = 0

    init(baseURL: URL, transport: HTTPTransport, store: TokenStore,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.baseURL = baseURL
        self.transport = transport
        self.store = store
        self.now = now
        (sessionExpirations, expirationContinuation) = AsyncStream<Void>.makeStream()
    }

    // MARK: AuthRepository

    func login(username: String, password: String) async throws {
        let request = Endpoint.login(username: username, password: password)
            .urlRequest(baseURL: baseURL, accessToken: nil)
        let (data, response) = try await send(request)

        switch response.statusCode {
        case 200..<300:
            guard let tokens = try? JSONCoding.makeDecoder().decode(TokenPair.self, from: data) else {
                throw APIError.decoding
            }
            try store.save(session(from: tokens))
        case 401:
            throw APIError.invalidCredentials
        default:
            throw APIError.from(status: response.statusCode, data: data)
        }
    }

    func logout() async {
        epoch += 1
        refreshTask?.cancel()
        refreshTask = nil
        try? store.clear()
    }

    func hasSession() async -> Bool {
        ((try? store.load()) ?? nil) != nil
    }

    // MARK: Tokens

    /// Devuelve un access token vigente, renovándolo de forma proactiva si está por vencer.
    func validAccessToken() async throws -> String {
        guard let current = try store.load() else { throw APIError.notAuthenticated }
        if current.accessTokenExpiresAt.timeIntervalSince(now()) > Self.expiryLeeway {
            return current.accessToken
        }
        return try await refreshedAccessToken(replacing: current.accessToken)
    }

    /// Renueva la sesión porque `stale` fue rechazado o está vencido. Llamadas concurrentes
    /// comparten una sola petición; si otra ya renovó, se devuelve el token nuevo sin red.
    func refreshedAccessToken(replacing stale: String) async throws -> String {
        guard let current = try store.load() else { throw APIError.notAuthenticated }
        if current.accessToken != stale { return current.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }

        let refreshToken = current.refreshToken
        let startEpoch = epoch
        let task = Task { try await self.performRefresh(refreshToken: refreshToken, epoch: startEpoch) }
        refreshTask = task
        defer { refreshTask = nil }
        // La Task no es hija de quien llama: si ese llamador se cancela, la renovación termina
        // igual y no se pierde el refresh token rotado.
        return try await task.value.accessToken
    }

    /// Descarta la sesión local y avisa a la UI.
    func expireSession() {
        epoch += 1
        try? store.clear()
        expirationContinuation.yield()
    }

    // MARK: Privado

    private func performRefresh(refreshToken: String, epoch startEpoch: Int) async throws -> StoredSession {
        let request = Endpoint.refresh(refreshToken: refreshToken)
            .urlRequest(baseURL: baseURL, accessToken: nil)
        let (data, response) = try await send(request)
        // El usuario cerró sesión (o la sesión expiró) mientras esperábamos: no guardar nada.
        guard epoch == startEpoch else { throw APIError.notAuthenticated }

        switch response.statusCode {
        case 200..<300:
            guard let tokens = try? JSONCoding.makeDecoder().decode(TokenPair.self, from: data) else {
                throw APIError.decoding
            }
            let session = session(from: tokens)
            try store.save(session)
            return session
        case 401:
            expireSession()
            throw APIError.sessionExpired
        default:
            // Fallo transitorio (500, etc.): conservamos la sesión para poder reintentar.
            throw APIError.from(status: response.statusCode, data: data)
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw APIError.network
        }
    }

    private func session(from tokens: TokenPair) -> StoredSession {
        StoredSession(accessToken: tokens.accessToken,
                      refreshToken: tokens.refreshToken,
                      accessTokenExpiresAt: now().addingTimeInterval(TimeInterval(tokens.expiresIn)))
    }
}
