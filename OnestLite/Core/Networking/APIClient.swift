import Foundation

/// Cliente autenticado: agrega el access token y, si el servidor responde 401, renueva la sesión
/// (una sola vez para todas las peticiones concurrentes) y reintenta la petición original.
final class APIClient: Sendable {
    private let baseURL: URL
    private let transport: HTTPTransport
    private let auth: AuthSession

    init(baseURL: URL, transport: HTTPTransport, auth: AuthSession) {
        self.baseURL = baseURL
        self.transport = transport
        self.auth = auth
    }

    func send<Response: Decodable>(_ endpoint: Endpoint, as type: Response.Type = Response.self) async throws -> Response {
        let data = try await perform(endpoint)
        do {
            return try JSONCoding.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private func perform(_ endpoint: Endpoint) async throws -> Data {
        guard endpoint.requiresAuth else {
            return try await execute(endpoint, accessToken: nil)
        }

        let token = try await auth.validAccessToken()
        do {
            return try await execute(endpoint, accessToken: token)
        } catch APIError.unauthorized {
            let fresh = try await auth.refreshedAccessToken(replacing: token)
            do {
                return try await execute(endpoint, accessToken: fresh)
            } catch APIError.unauthorized {
                // Renovamos y aun así nos rechazan: la sesión no es recuperable.
                await auth.expireSession()
                throw APIError.sessionExpired
            }
        }
    }

    private func execute(_ endpoint: Endpoint, accessToken: String?) async throws -> Data {
        let request = endpoint.urlRequest(baseURL: baseURL, accessToken: accessToken)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw APIError.network
        }

        guard (200..<300).contains(response.statusCode) else {
            throw APIError.from(status: response.statusCode, data: data)
        }
        return data
    }
}
