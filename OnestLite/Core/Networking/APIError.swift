import Foundation

enum APIError: Error, Equatable, Sendable {
    /// 401 genérico; el cliente lo intercepta para renovar el token.
    case unauthorized
    case invalidCredentials
    /// La sesión ya no es recuperable: hay que volver a iniciar sesión.
    case sessionExpired
    case notAuthenticated
    case notFound
    case badRequest(message: String)
    case validation(message: String, fields: [String: String])
    case server(status: Int)
    case network
    case decoding
    case unexpected(status: Int)

    /// Errores que tiene sentido reintentar (con la misma Idempotency-Key en escrituras).
    var isRetryable: Bool {
        switch self {
        case .server, .network: return true
        default: return false
        }
    }

    /// Mensaje listo para mostrar al usuario.
    var userMessage: String {
        switch self {
        case .invalidCredentials:
            return "Usuario o contraseña incorrectos."
        case .unauthorized, .sessionExpired, .notAuthenticated:
            return "Tu sesión expiró. Inicia sesión de nuevo."
        case .notFound:
            return "No encontramos lo que buscabas."
        case .badRequest(let message), .validation(let message, _):
            return message
        case .server:
            return "Tuvimos un problema en el servidor. Inténtalo de nuevo."
        case .network:
            return "No hay conexión. Revisa tu internet e inténtalo de nuevo."
        case .decoding, .unexpected:
            return "Recibimos una respuesta inesperada. Inténtalo de nuevo."
        }
    }

    /// Traduce una respuesta no exitosa. Los llamadores sobrescriben los casos que tienen
    /// otro significado en su contexto (p. ej. 401 en login = credenciales inválidas).
    static func from(status: Int, data: Data) -> APIError {
        let body = try? JSONCoding.makeDecoder().decode(APIErrorEnvelope.self, from: data).error
        switch status {
        case 401: return .unauthorized
        case 404: return .notFound
        case 400: return .badRequest(message: body?.message ?? "Solicitud inválida.")
        case 422: return .validation(message: body?.message ?? "Datos inválidos.", fields: body?.fields ?? [:])
        case 500...599: return .server(status: status)
        default: return .unexpected(status: status)
        }
    }
}

extension Error {
    /// Mensaje para el usuario; `nil` cuando el error es una cancelación y no hay nada que mostrar.
    var userFacingMessage: String? {
        if self is CancellationError { return nil }
        if let apiError = self as? APIError { return apiError.userMessage }
        return "Ocurrió un error inesperado. Inténtalo de nuevo."
    }
}
