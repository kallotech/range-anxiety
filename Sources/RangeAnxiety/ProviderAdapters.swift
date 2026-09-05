import Foundation

final class CodexProviderAdapter: UsageProviderAdapter {
    let id = ProviderID.codex
    private let client = CodexUsageClient()

    func fetch(completion: @escaping (Result<ProviderFetchResult, Error>) -> Void) {
        client.fetch { result in
            switch result {
            case .success(let snapshot):
                completion(.success(ProviderFetchResult(
                    usage: ProviderUsage(id: .codex, tokens: nil, spendUSD: nil,
                                         period: .today, secondaryMetric: nil, state: .available),
                    quotaWindows: snapshot.windows
                )))
            case .failure(let error): completion(.failure(error))
            }
        }
    }
}

final class ClaudeCodeProviderAdapter: UsageProviderAdapter {
    let id = ProviderID.claudeCode
    private let client = ClaudeUsageCaptureClient()

    func fetch(completion: @escaping (Result<ProviderFetchResult, Error>) -> Void) {
        client.fetch { result in
            switch result {
            case .success(let windows):
                completion(.success(ProviderFetchResult(
                    usage: ProviderUsage(id: .claudeCode, tokens: nil, spendUSD: nil,
                                         period: .today, secondaryMetric: "Captured locally from Claude Code", state: .available),
                    quotaWindows: windows
                )))
            case .failure(let error): completion(.failure(error))
            }
        }
    }
}

final class OpenRouterProviderAdapter: UsageProviderAdapter {
    let id = ProviderID.openRouter
    private let client = OpenRouterUsageClient()

    func fetch(completion: @escaping (Result<ProviderFetchResult, Error>) -> Void) {
        do {
            guard let saved = try ProviderCredentialStore.read(.openRouter) else {
                completion(.failure(ProviderAdapterError.notConfigured)); return
            }
            client.fetch(key: saved.key) { result in
                switch result {
                case .success(let snapshot):
                    completion(.success(ProviderFetchResult(
                        usage: ProviderUsage(id: .openRouter, tokens: snapshot.tokensToday,
                                             spendUSD: snapshot.spendTodayUSD, period: .today,
                                             secondaryMetric: nil, isPartial: snapshot.isPartial, state: .available),
                        quotaWindows: []
                    )))
                case .failure(let error): completion(.failure(error))
                }
            }
        } catch { completion(.failure(error)) }
    }
}

enum ProviderAdapterFactory {
    static func makeAdapters() -> [ProviderID: any UsageProviderAdapter] {
        let adapters: [any UsageProviderAdapter] = [
            CodexProviderAdapter(), ClaudeCodeProviderAdapter(), OpenRouterProviderAdapter(), OpenAIProviderAdapter(),
            AnthropicProviderAdapter(), XAIProviderAdapter(), MistralProviderAdapter(),
            TogetherProviderAdapter(), FireworksProviderAdapter(), GroqProviderAdapter()
        ]
        return Dictionary(uniqueKeysWithValues: adapters.map { ($0.id, $0) })
    }
}
