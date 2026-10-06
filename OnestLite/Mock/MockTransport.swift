import Foundation

/// Implementa `HTTPTransport` contra `MockBackend`. Es lo único que hay que reemplazar por
/// `URLSessionTransport` (y cambiar la `baseURL`) para hablar con un servidor real.
struct MockTransport: HTTPTransport {
    private let backend: MockBackend

    init(backend: MockBackend) {
        self.backend = backend
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        let mockRequest = MockRequest(method: request.httpMethod ?? "GET",
                                      path: url.path,
                                      headers: request.allHTTPHeaderFields ?? [:],
                                      body: request.httpBody ?? Data())
        let response = try await backend.handle(mockRequest)
        guard let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1",
                                         headerFields: ["Content-Type": "application/json"]) else {
            throw URLError(.badServerResponse)
        }
        return (response.body, http)
    }
}
