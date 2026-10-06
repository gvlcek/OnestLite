import Foundation

enum JSONCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encode<T: Encodable>(_ value: T) -> Data {
        // Solo codificamos structs de tipos simples; un fallo aquí es un error de programación.
        do {
            return try makeEncoder().encode(value)
        } catch {
            assertionFailure("No se pudo codificar \(T.self): \(error)")
            return Data()
        }
    }
}

struct Endpoint: Sendable {
    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
    }

    let method: Method
    let path: String
    var body: Data?
    var headers: [String: String] = [:]
    var requiresAuth = true

    func urlRequest(baseURL: URL, accessToken: String?) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method.rawValue
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

extension Endpoint {
    static func login(username: String, password: String) -> Endpoint {
        Endpoint(method: .post, path: "/auth/login",
                 body: JSONCoding.encode(LoginRequest(username: username, password: password)),
                 requiresAuth: false)
    }

    static func refresh(refreshToken: String) -> Endpoint {
        Endpoint(method: .post, path: "/auth/refresh",
                 body: JSONCoding.encode(RefreshRequest(refreshToken: refreshToken)),
                 requiresAuth: false)
    }

    static var loans: Endpoint {
        Endpoint(method: .get, path: "/loans")
    }

    static func loan(id: String) -> Endpoint {
        Endpoint(method: .get, path: "/loans/\(id)")
    }

    static func quote(_ terms: LoanTerms) -> Endpoint {
        Endpoint(method: .post, path: "/loans/quote", body: JSONCoding.encode(terms))
    }

    static func createLoan(_ terms: LoanTerms, idempotencyKey: String) -> Endpoint {
        Endpoint(method: .post, path: "/loans", body: JSONCoding.encode(terms),
                 headers: ["Idempotency-Key": idempotencyKey])
    }
}
