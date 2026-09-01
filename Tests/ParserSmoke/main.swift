import Foundation

// Run from the repository root when XCTest is unavailable:
// swiftc Sources/RangeAnxiety/Models.swift Sources/RangeAnxiety/ProviderCatalog.swift \
//   Sources/RangeAnxiety/ProviderCredentialStore.swift Sources/RangeAnxiety/MajorProviderAdapters.swift \
//   Tests/ParserSmoke/main.swift -framework Security -framework LocalAuthentication \
//   -o /tmp/rangeanxiety-parser-smoke && /tmp/rangeanxiety-parser-smoke

func data(_ json: String) -> Data { Data(json.utf8) }
func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    guard actual == expected else {
        fputs("FAIL \(label): \(actual) != \(expected)\n", stderr)
        exit(1)
    }
}

do {
    expect(QuotaActivity(pointsPerMinute: 0.04), .calm, "Calm quota animation")
    expect(QuotaActivity(pointsPerMinute: 0.12), .active, "Active quota animation")
    expect(QuotaActivity(pointsPerMinute: 0.40), .rapid, "Rapid quota animation")
    expect(try OpenAIProviderAdapter.parseTokens(data("""
    {"data":[{"results":[{"input_tokens":100,"output_tokens":20},{"input_tokens":"3","output_tokens":"2"}]}]}
    """)), 125, "OpenAI tokens")
    expect(try AnthropicProviderAdapter.parseTokens(data("""
    {"data":[{"results":[{"uncached_input_tokens":100,"cache_read_input_tokens":10,"output_tokens":20,"cache_creation":{"ephemeral_5m_input_tokens":4,"ephemeral_1h_input_tokens":1}}]}]}
    """)), 135, "Anthropic tokens")
    expect(try TogetherProviderAdapter.parseCost(data("""
    {"data":[{"line_items":[{"cost":"0.75"},{"cost":0.25}]}]}
    """)), 1.0, "Together cost")
    expect(try FireworksProviderAdapter.parseCost(data("""
    {"lineItems":[{"totalCost":{"units":"2","nanos":500000000,"currencyCode":"USD"}}]}
    """)), 2.5, "Fireworks cost")
    expect(try GroqProviderAdapter.parse(data("""
    {"status":"success","data":{"result":[{"value":[1700000000,"321"]}]}}
    """)), 321, "Groq rate")
    print("All provider parser smoke checks passed")
} catch {
    fputs("FAIL unexpected error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
