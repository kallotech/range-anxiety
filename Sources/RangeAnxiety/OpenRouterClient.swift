import Foundation

enum OpenRouterClientError: LocalizedError {
    case invalidKey
    case managementKeyRequired
    case rateLimited
    case server(Int)
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "OpenRouter rejected the saved key."
        case .managementKeyRequired: return "OpenRouter analytics requires a management key."
        case .rateLimited: return "OpenRouter is temporarily rate limiting usage checks."
        case .server(let status): return "OpenRouter returned HTTP \(status)."
        case .invalidResponse: return "OpenRouter returned an unexpected analytics response."
        case .requestFailed(let message): return "OpenRouter could not be reached: \(message)"
        }
    }
}

final class OpenRouterUsageClient {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetch(key: String, completion: @escaping (Result<OpenRouterSnapshot, Error>) -> Void) {
        guard let url = URL(string: "https://openrouter.ai/api/v1/analytics/query") else {
            completion(.failure(OpenRouterClientError.invalidResponse))
            return
        }

        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let body: [String: Any] = [
            "metrics": ["tokens_total", "tokens_prompt", "tokens_completion", "total_usage"],
            "time_range": ["start": formatter.string(from: start), "end": formatter.string(from: now)],
            "limit": 100
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("RangeAnxiety", forHTTPHeaderField: "X-OpenRouter-Title")

        do { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        catch {
            completion(.failure(OpenRouterClientError.invalidResponse))
            return
        }

        session.dataTask(with: request) { data, response, error in
            let result: Result<OpenRouterSnapshot, Error>
            if let error {
                result = .failure(OpenRouterClientError.requestFailed(error.localizedDescription))
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                switch http.statusCode {
                case 401: result = .failure(OpenRouterClientError.invalidKey)
                case 403: result = .failure(OpenRouterClientError.managementKeyRequired)
                case 429: result = .failure(OpenRouterClientError.rateLimited)
                default: result = .failure(OpenRouterClientError.server(http.statusCode))
                }
            } else if let data {
                do { result = .success(try Self.parse(data: data)) }
                catch { result = .failure(error) }
            } else {
                result = .failure(OpenRouterClientError.invalidResponse)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    static func parse(data: Data) throws -> OpenRouterSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let envelope = object["data"] as? [String: Any],
              let rows = envelope["data"] as? [[String: Any]] else {
            throw OpenRouterClientError.invalidResponse
        }

        var tokens: Int64 = 0
        var spend: Double = 0
        for row in rows {
            tokens += integer(row["tokens_total"]) ?? 0
            spend += number(row["total_usage"]) ?? 0
        }
        let metadata = envelope["metadata"] as? [String: Any]
        return OpenRouterSnapshot(
            tokensToday: tokens,
            spendTodayUSD: spend,
            isPartial: metadata?["truncated"] as? Bool ?? false
        )
    }

    private static func integer(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
