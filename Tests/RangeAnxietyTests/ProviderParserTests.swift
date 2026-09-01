import Foundation
import XCTest
@testable import RangeAnxiety

final class ProviderParserTests: XCTestCase {
    func testQuotaActivityThresholds() {
        XCTAssertEqual(QuotaActivity(pointsPerMinute: 0.04), .calm)
        XCTAssertEqual(QuotaActivity(pointsPerMinute: 0.12), .active)
        XCTAssertEqual(QuotaActivity(pointsPerMinute: 0.40), .rapid)
    }

    func testOpenAIUsageAndCost() throws {
        XCTAssertEqual(try OpenAIProviderAdapter.parseTokens(json("""
        {"data":[{"results":[{"input_tokens":100,"output_tokens":20},{"input_tokens":"3","output_tokens":"2"}]}]}
        """)), 125)
        XCTAssertEqual(try OpenAIProviderAdapter.parseCost(json("""
        {"data":[{"results":[{"amount":{"value":0.12,"currency":"usd"}}]}]}
        """)), 0.12, accuracy: 0.000_001)
    }

    func testAnthropicUsageAndCost() throws {
        XCTAssertEqual(try AnthropicProviderAdapter.parseTokens(json("""
        {"data":[{"results":[{"uncached_input_tokens":100,"cache_read_input_tokens":10,"output_tokens":20,"cache_creation":{"ephemeral_5m_input_tokens":4,"ephemeral_1h_input_tokens":1}}]}]}
        """)), 135)
        XCTAssertEqual(try AnthropicProviderAdapter.parseCost(json("""
        {"data":[{"results":[{"amount":"25"}]}]}
        """)), 0.25, accuracy: 0.000_001)
    }

    func testSpendOnlyProviders() throws {
        let xai = try XAIProviderAdapter.parse(json("""
        {"timeSeries":[{"dataPoints":[{"values":[{"name":"usd","value":"1.25"}]}]}],"limitReached":true}
        """))
        XCTAssertEqual(xai.spend, 1.25, accuracy: 0.000_001)
        XCTAssertTrue(xai.isPartial)

        XCTAssertEqual(try TogetherProviderAdapter.parseCost(json("""
        {"data":[{"line_items":[{"cost":"0.75"},{"cost":0.25}]}]}
        """)), 1.0, accuracy: 0.000_001)

        XCTAssertEqual(try FireworksProviderAdapter.parseCost(json("""
        {"lineItems":[{"totalCost":{"units":"2","nanos":500000000,"currencyCode":"USD"}}]}
        """)), 2.5, accuracy: 0.000_001)
    }

    func testMistralAndGroq() throws {
        let mistral = try MistralProviderAdapter.parse(json("""
        {"data":[{"input_tokens":40,"output_tokens":2,"cost":"0.04"},{"total_tokens":8,"total_cost":0.01}]}
        """))
        XCTAssertEqual(mistral.tokens, 50)
        XCTAssertEqual(mistral.spend ?? -1, 0.05, accuracy: 0.000_001)

        XCTAssertEqual(try GroqProviderAdapter.parse(json("""
        {"status":"success","data":{"result":[{"value":[1700000000,"321"]}]}}
        """)), 321)
    }

    private func json(_ value: String) -> Data { Data(value.utf8) }
}
