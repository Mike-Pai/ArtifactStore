import Foundation

struct DemoBackendClient: Sendable {
    enum ClientError: LocalizedError, Equatable {
        case invalidBaseURL
        case invalidResponse
        case httpStatus(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "Backend URL is invalid."
            case .invalidResponse:
                return "Backend returned an invalid response."
            case .httpStatus(let status, let body):
                if body.isEmpty {
                    return "Backend returned HTTP \(status)."
                }
                return "Backend returned HTTP \(status): \(body)"
            }
        }
    }

    let baseURL: URL
    let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURLString: String, session: URLSession = .shared) throws {
        guard let url = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme),
              url.host != nil
        else {
            throw ClientError.invalidBaseURL
        }
        self.baseURL = url
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func health() async throws {
        let _: HealthResponse = try await get("health")
    }

    func createRun(
        kind: String = "pytest",
        target: String = "auth_expiry",
        model: String = "deepseek-v4-pro"
    ) async throws -> CreateRunResponse {
        try await post(
            "runs",
            body: CreateRunRequest(kind: kind, target: target, model: model)
        )
    }

    func fetchRun(runID: String) async throws -> RunSummary {
        try await get("runs/\(runID)")
    }

    func fetchEvents(runID: String, after seq: Int) async throws -> [RunEvent] {
        var components = URLComponents(url: endpoint("runs/\(runID)/events"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "after", value: String(seq))]
        guard let url = components?.url else {
            throw ClientError.invalidBaseURL
        }
        let response: EventsResponse = try await request(urlRequest: URLRequest(url: url))
        return response.events
    }

    func fetchLatestTrace() async throws -> TraceResponse {
        try await get("traces/latest")
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(urlRequest: URLRequest(url: endpoint(path)))
    }

    private func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await self.request(urlRequest: request)
    }

    private func request<T: Decodable>(urlRequest: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.httpStatus(http.statusCode, body)
        }
        return try decoder.decode(T.self, from: data)
    }

    private func endpoint(_ path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { url, component in
            url.appendingPathComponent(String(component))
        }
    }
}

private struct HealthResponse: Codable {
    let status: String
}
