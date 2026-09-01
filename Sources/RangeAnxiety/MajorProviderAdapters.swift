import Foundation

enum ProviderHTTPError: LocalizedError {
    case invalidRequest
    case unauthorized(String)
    case forbidden(String)
    case rateLimited(String)
    case server(String, Int)
    case invalidResponse(String)
    case requestFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest: return "The usage request could not be created."
        case .unauthorized(let provider): return "\(provider) rejected the saved credential."
        case .forbidden(let provider): return "\(provider) says this credential cannot read organization usage."
        case .rateLimited(let provider): return "\(provider) is temporarily rate limiting usage checks."
        case .server(let provider, let status): return "\(provider) returned HTTP \(status)."
        case .invalidResponse(let provider): return "\(provider) returned an unexpected usage response."
        case .requestFailed(let provider, let message): return "\(provider) could not be reached: \(message)"
        }
    }
}

enum ProviderHTTPClient {
    static func perform(_ request: URLRequest, provider: String,
                        completion: @escaping (Result<Data, Error>) -> Void) {
        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<Data, Error>
            if let error {
                result = .failure(ProviderHTTPError.requestFailed(provider, error.localizedDescription))
            } else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                switch http.statusCode {
                case 401: result = .failure(ProviderHTTPError.unauthorized(provider))
                case 403: result = .failure(ProviderHTTPError.forbidden(provider))
                case 429: result = .failure(ProviderHTTPError.rateLimited(provider))
                default: result = .failure(ProviderHTTPError.server(provider, http.statusCode))
                }
            } else if let data {
                result = .success(data)
            } else {
                result = .failure(ProviderHTTPError.invalidResponse(provider))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}

enum ProviderDateFormatting {
    static var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }
    static var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? startOfToday
    }
    static func unix(_ date: Date) -> String { String(Int(date.timeIntervalSince1970)) }
    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    static func monthAndYear() -> (month: String, numericMonth: String, year: String) {
        func string(_ format: String) -> String {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            return formatter.string(from: Date())
        }
        return (string("yyyy-MM"), string("M"), string("yyyy"))
    }
}

enum ProviderJSON {
    static func object(_ data: Data, provider: String) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderHTTPError.invalidResponse(provider)
        }
        return object
    }
    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
    static func integer(_ value: Any?) -> Int64? {
        guard let value = number(value) else { return nil }
        return Int64(value.rounded())
    }
    static func rows(_ value: Any?) -> [[String: Any]] {
        if let rows = value as? [[String: Any]] { return rows }
        if let dictionary = value as? [String: Any] {
            for key in ["data", "results", "items", "line_items", "lineItems"] {
                if let rows = dictionary[key] as? [[String: Any]] { return rows }
            }
        }
        return []
    }
    static func directNumber(in dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys where number(dictionary[key]) != nil { return number(dictionary[key]) }
        return nil
    }
}

private func credential(for provider: ProviderID) throws -> ProviderCredential {
    guard let saved = try ProviderCredentialStore.read(provider) else { throw ProviderAdapterError.notConfigured }
    return saved
}

private func getRequest(url: URL, bearer: String? = nil, apiKey: String? = nil) -> URLRequest {
    var request = URLRequest(url: url)
    request.timeoutInterval = 25
    if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
    if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
    return request
}

final class OpenAIProviderAdapter: UsageProviderAdapter {
    let id = ProviderID.openAI

    func fetch(completion: @escaping (Result<ProviderFetchResult, Error>) -> Void) {
        do {
            let key = try credential(for: id).key
            let start = ProviderDateFormatting.unix(ProviderDateFormatting.startOfToday)
            let end = ProviderDateFormatting.unix(Date())
            guard let usageURL = URL(string: "https://api.openai.com/v1/organization/usage/completions?start_time=\(start)&end_time=\(end)&bucket_width=1d&limit=7"),
                  let costsURL = URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(start)&end_time=\(end)&bucket_width=1d&limit=7") else {
                throw ProviderHTTPError.invalidRequest
            }
            ProviderHTTPClient.perform(getRequest(url: usageURL, bearer: key), provider: "OpenAI") { usageResult in
                do {
                    let tokens = try Self.parseTokens(try usageResult.get())
                    ProviderHTTPClient.perform(getRequest(url: costsURL, bearer: key), provider: "OpenAI") { costResult in
                        let spend = try? Self.parseCost(try costResult.get())
                        completion(.success(ProviderFetchResult(
                            usage: ProviderUsage(id: .openAI, tokens: tokens, spendUSD: spend, period: .today,
                                                 secondaryMetric: spend == nil ? "Cost unavailable" : nil,
                                                 isPartial: spend == nil, state: .available), quotaWindows: [])))
                    }
                } catch { completion(.failure(error)) }
            }
        } catch { completion(.failure(error)) }
    }

    static func parseTokens(_ data: Data) throws -> Int64 {
        let object = try ProviderJSON.object(data, provider: "OpenAI")
        var total: Int64 = 0
        for bucket in ProviderJSON.rows(object["data"]) {
            for row in ProviderJSON.rows(bucket["results"]) {
                total += ProviderJSON.integer(row["input_tokens"]) ?? 0
                total += ProviderJSON.integer(row["output_tokens"]) ?? 0
            }
        }
        return total
    }

    static func parseCost(_ data: Data) throws -> Double {
        let object = try ProviderJSON.object(data, provider: "OpenAI")
        var total = 0.0
        for bucket in ProviderJSON.rows(object["data"]) {
            for row in ProviderJSON.rows(bucket["results"]) {
                if let amount = row["amount"] as? [String: Any] { total += ProviderJSON.number(amount["value"]) ?? 0 }
            }
        }
        return total
    }
}

final class AnthropicProviderAdapter: UsageProviderAdapter {
    let id = ProviderID.anthropic

    func fetch(completion: @escaping (Result<ProviderFetchResult, Error>) -> Void) {
        do {
            let key = try credential(for: id).key
            let start = ProviderDateFormatting.iso(ProviderDateFormatting.startOfToday)
            let end = ProviderDateFormatting.iso(Date())
            var usageComponents = URLComponents(string: "https://api.anthropic.com/v1/organizations/usage_report/messages")!
            usageComponents.queryItems = [URLQueryItem(name: "starting_at", value: start), URLQueryItem(name: "ending_at", value: end), URLQueryItem(name: "bucket_width", value: "1d"), URLQueryItem(name: "limit", value: "7")]
            var costComponents = URLComponents(string: "https://api.anthropic.com/v1/organizations/cost_report")!
            costComponents.queryItems = [URLQueryItem(name: "starting_at", value: start), URLQueryItem(name: "ending_at", value: end), URLQueryItem(name: "bucket_width", value: "1d"), URLQueryItem(name: "limit", value: "7")]
            guard let usageURL = usageComponents.url, let costURL = costComponents.url else { throw ProviderHTTPError.invalidRequest }
            var usageRequest = getRequest(url: usageURL, apiKey: key)
            usageRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            ProviderHTTPClient.perform(usageRequest, provider: "Anthropic") { usageResult in
                do {
                    let tokens = try Self.parseTokens(try usageResult.get())
                    var costRequest = getRequest(url: costURL, apiKey: key)
                    costRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    ProviderHTTPClient.perform(costRequest, provider: "Anthropic") { costResult in
                        let spend = try? Self.parseCost(try costResult.get())
                        completion(.success(ProviderFetchResult(
                            usage: ProviderUsage(id: .anthropic, tokens: tokens, spendUSD: spend, period: .today,
                                                 secondaryMetric: spend == nil ? "Cost unavailable" : nil,
                                                 isPartial: spend == nil, state: .available), quotaWindows: [])))
                    }
                } catch { completion(.failure(error)) }
            }
        } catch { completion(.failure(error)) }
    }

    static func parseTokens(_ data: Data) throws -> Int64 {
        let object = try ProviderJSON.object(data, provider: "Anthropic")
        var total: Int64 = 0
        for bucket in ProviderJSON.rows(object["data"]) {
            for row in ProviderJSON.rows(bucket["results"]) {
                total += ProviderJSON.integer(row["uncached_input_tokens"]) ?? 0
                total += ProviderJSON.integer(row["cache_read_input_tokens"]) ?? 0
                total += ProviderJSON.integer(row["cache_creation_input_tokens"]) ?? 0
                total += ProviderJSON.integer(row["output_tokens"]) ?? 0
                if let creation = row["cache_creation"] as? [String: Any] {
                    total += ProviderJSON.integer(creation["ephemeral_5m_input_tokens"]) ?? 0
                    total += ProviderJSON.integer(creation["ephemeral_1h_input_tokens"]) ?? 0
                }
            }
        }
        return total
    }

    static func parseCost(_ data: Data) throws -> Double {
        let object = try ProviderJSON.object(data, provider: "Anthropic")
        var cents = 0.0
        for bucket in ProviderJSON.rows(object["data"]) {
            for row in ProviderJSON.rows(bucket["results"]) { cents += ProviderJSON.number(row["amount"]) ?? 0 }
        }
        return cents / 100
    }
}

final class XAIProviderAdapter: UsageProviderAdapter {
    let id = ProviderID.xAI

    func fetch(completion: @escaping (Result<ProviderFetchResult, Error>) -> Void) {
        do {
            let saved = try credential(for: id)
            guard let teamID = saved.auxiliary?.trimmingCharacters(in: .whitespacesAndNewlines), !teamID.isEmpty else {
                throw ProviderAdapterError.invalidConfiguration("Enter the xAI Team ID.")
            }
            guard let url = URL(string: "https://management-api.x.ai/v1/billing/teams/\(teamID)/usage") else { throw ProviderHTTPError.invalidRequest }
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let body: [String: Any] = ["analyticsRequest": [
                "timeRange": ["startTime": formatter.string(from: ProviderDateFormatting.startOfMonth),
                              "endTime": formatter.string(from: Date()), "timezone": TimeZone.current.identifier],
                "timeUnit": "TIME_UNIT_DAY",
                "values": [["name": "usd", "aggregation": "AGGREGATION_SUM"]],
                "groupBy": ["description"], "filters": []
            ]]
            var request = getRequest(url: url, bearer: saved.key)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            ProviderHTTPClient.perform(request, provider: "xAI") { result in
                do {
                    let parsed = try Self.parse(try result.get())
                    completion(.success(ProviderFetchResult(
                        usage: ProviderUsage(id: .xAI, tokens: nil, spendUSD: parsed.spend, period: .monthToDate,
                                             secondaryMetric: "Spend reporting", isPartial: parsed.isPartial, state: .available),
                        quotaWindows: [])))
                } catch { completion(.failure(error)) }
            }
        } catch { completion(.failure(error)) }
    }

    static func parse(_ data: Data) throws -> (spend: Double, isPartial: Bool) {
        let object = try ProviderJSON.object(data, provider: "xAI")
        var spend = 0.0
        for series in ProviderJSON.rows(object["timeSeries"]) {
            for point in ProviderJSON.rows(series["dataPoints"]) {
                for value in ProviderJSON.rows(point["values"]) where (value["name"] as? String)?.lowercased() == "usd" {
                    spend += ProviderJSON.number(value["value"]) ?? 0
                }
            }
        }
        return (spend, object["limitReached"] as? Bool ?? false)
    }
}

final class TogetherProviderAdapter: UsageProviderAdapter {
    let id = ProviderID.together

    func fetch(completion: @escaping (Result<ProviderFetchResult, Error>) -> Void) {
        do {
            let saved = try credential(for: id)
            var components = URLComponents(string: "https://api.together.ai/v1/billing/usage")!
            var items = [URLQueryItem(name: "month", value: ProviderDateFormatting.monthAndYear().month),
                         URLQueryItem(name: "granularity", value: "day")]
            if let organization = saved.auxiliary, !organization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(URLQueryItem(name: "organization_id", value: organization))
            }
            components.queryItems = items
            guard let url = components.url else { throw ProviderHTTPError.invalidRequest }
            ProviderHTTPClient.perform(getRequest(url: url, bearer: saved.key), provider: "Together AI") { result in
                do {
                    let spend = try Self.parseCost(try result.get())
                    completion(.success(ProviderFetchResult(
                        usage: ProviderUsage(id: .together, tokens: nil, spendUSD: spend, period: .throughYesterday,
                                             secondaryMetric: "Spend reporting", state: .available), quotaWindows: [])))
                } catch { completion(.failure(error)) }
            }
        } catch { completion(.failure(error)) }
    }

    static func parseCost(_ data: Data) throws -> Double {
        let object = try ProviderJSON.object(data, provider: "Together AI")
        var total = 0.0
        for day in ProviderJSON.rows(object["data"]) {
            for item in ProviderJSON.rows(day["line_items"]) { total += ProviderJSON.number(item["cost"]) ?? 0 }
        }
        return total
    }
}

final class FireworksProviderAdapter: UsageProviderAdapter {
    let id = ProviderID.fireworks

    func fetch(completion: @escaping (Result<ProviderFetchResult, Error>) -> Void) {
        do {
            let saved = try credential(for: id)
            guard let account = saved.auxiliary?.trimmingCharacters(in: .whitespacesAndNewlines), !account.isEmpty else {
                throw ProviderAdapterError.invalidConfiguration("Enter the Fireworks Account ID.")
            }
            var components = URLComponents(string: "https://api.fireworks.ai/v1/accounts/\(account)/billing/summary")!
            components.queryItems = [
                URLQueryItem(name: "startTime", value: ProviderDateFormatting.iso(ProviderDateFormatting.startOfMonth)),
                URLQueryItem(name: "endTime", value: ProviderDateFormatting.iso(Date()))
            ]
            guard let url = components.url else { throw ProviderHTTPError.invalidRequest }
            ProviderHTTPClient.perform(getRequest(url: url, bearer: saved.key), provider: "Fireworks AI") { result in
                do {
                    let spend = try Self.parseCost(try result.get())
                    completion(.success(ProviderFetchResult(
                        usage: ProviderUsage(id: .fireworks, tokens: nil, spendUSD: spend, period: .monthToDate,
                                             secondaryMetric: "Spend reporting", state: .available), quotaWindows: [])))
                } catch { completion(.failure(error)) }
            }
        } catch { completion(.failure(error)) }
    }

    static func parseCost(_ data: Data) throws -> Double {
        let object = try ProviderJSON.object(data, provider: "Fireworks AI")
        var total = 0.0
        for item in ProviderJSON.rows(object["lineItems"]) {
            guard let money = item["totalCost"] as? [String: Any] else { continue }
            total += ProviderJSON.number(money["units"]) ?? 0
            total += (ProviderJSON.number(money["nanos"]) ?? 0) / 1_000_000_000
        }
        return total
    }
}

final class MistralProviderAdapter: UsageProviderAdapter {
    let id = ProviderID.mistral

    func fetch(completion: @escaping (Result<ProviderFetchResult, Error>) -> Void) {
        do {
            let key = try credential(for: id).key
            let date = ProviderDateFormatting.monthAndYear()
            guard let url = URL(string: "https://api.mistral.ai/v1/admin/usage?month=\(date.numericMonth)&year=\(date.year)") else {
                throw ProviderHTTPError.invalidRequest
            }
            ProviderHTTPClient.perform(getRequest(url: url, apiKey: key), provider: "Mistral AI") { result in
                do {
                    let parsed = try Self.parse(try result.get())
                    completion(.success(ProviderFetchResult(
                        usage: ProviderUsage(id: .mistral, tokens: parsed.tokens, spendUSD: parsed.spend,
                                             period: .monthToDate, secondaryMetric: nil, state: .available),
                        quotaWindows: [])))
                } catch { completion(.failure(error)) }
            }
        } catch { completion(.failure(error)) }
    }

    static func parse(_ data: Data) throws -> (tokens: Int64?, spend: Double?) {
        let object = try ProviderJSON.object(data, provider: "Mistral AI")
        let directTokens = ProviderJSON.directNumber(in: object, keys: ["total_tokens", "totalTokens"])
        let directCost = ProviderJSON.directNumber(in: object, keys: ["total_cost", "totalCost", "cost"])
        if directTokens != nil || directCost != nil {
            return (directTokens.map { Int64($0.rounded()) }, directCost)
        }
        let rows = ProviderJSON.rows(object["data"] ?? object["results"] ?? object["items"])
        var tokenTotal: Int64 = 0
        var costTotal = 0.0
        var sawTokens = false
        var sawCost = false
        for row in rows {
            if let total = ProviderJSON.directNumber(in: row, keys: ["total_tokens", "totalTokens", "tokens"]) {
                tokenTotal += Int64(total.rounded()); sawTokens = true
            } else {
                let input = ProviderJSON.directNumber(in: row, keys: ["input_tokens", "prompt_tokens"]) ?? 0
                let output = ProviderJSON.directNumber(in: row, keys: ["output_tokens", "completion_tokens"]) ?? 0
                if input != 0 || output != 0 { tokenTotal += Int64((input + output).rounded()); sawTokens = true }
            }
            if let cost = ProviderJSON.directNumber(in: row, keys: ["total_cost", "cost", "amount"]) {
                costTotal += cost; sawCost = true
            }
        }
        guard sawTokens || sawCost else { throw ProviderHTTPError.invalidResponse("Mistral AI") }
        return (sawTokens ? tokenTotal : nil, sawCost ? costTotal : nil)
    }
}

final class GroqProviderAdapter: UsageProviderAdapter {
    let id = ProviderID.groq

    func fetch(completion: @escaping (Result<ProviderFetchResult, Error>) -> Void) {
        do {
            let key = try credential(for: id).key
            let query = "sum(model_project_id:tokens_in:rate5m) + sum(model_project_id:tokens_out:rate5m)"
            var components = URLComponents(string: "https://api.groq.com/v1/metrics/prometheus/api/v1/query")!
            components.queryItems = [URLQueryItem(name: "query", value: query)]
            guard let url = components.url else { throw ProviderHTTPError.invalidRequest }
            ProviderHTTPClient.perform(getRequest(url: url, bearer: key), provider: "GroqCloud") { result in
                do {
                    let tokens = try Self.parse(try result.get())
                    completion(.success(ProviderFetchResult(
                        usage: ProviderUsage(id: .groq, tokens: tokens, spendUSD: nil, period: .recentRate,
                                             secondaryMetric: "Enterprise metric", state: .available), quotaWindows: [])))
                } catch { completion(.failure(error)) }
            }
        } catch { completion(.failure(error)) }
    }

    static func parse(_ data: Data) throws -> Int64 {
        let object = try ProviderJSON.object(data, provider: "GroqCloud")
        guard let envelope = object["data"] as? [String: Any] else { throw ProviderHTTPError.invalidResponse("GroqCloud") }
        var total = 0.0
        for row in ProviderJSON.rows(envelope["result"]) {
            if let value = row["value"] as? [Any], value.count > 1 { total += ProviderJSON.number(value[1]) ?? 0 }
        }
        return Int64(total.rounded())
    }
}
