import Foundation

struct QuotaWindow: Identifiable {
    let id: String
    let title: String
    let usedPercent: Double
    let durationMinutes: Int
    let resetsAt: Date?

    var remainingPercent: Double { min(100, max(0, 100 - usedPercent)) }
}

enum QuotaActivity: Equatable {
    case calm
    case active
    case rapid

    init(pointsPerMinute: Double) {
        switch pointsPerMinute {
        case 0.35...: self = .rapid
        case 0.08...: self = .active
        default: self = .calm
        }
    }

    var helpText: String {
        switch self {
        case .calm: return "Quota usage is steady"
        case .active: return "Quota usage is increasing"
        case .rapid: return "Quota usage is increasing quickly"
        }
    }
}

enum ProviderID: String, CaseIterable, Codable, Identifiable {
    case codex
    case openRouter
    case openAI
    case anthropic
    case xAI
    case mistral
    case together
    case fireworks
    case groq
    case gemini
    case deepSeek
    case azureOpenAI

    var id: String { rawValue }
}

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case quotaRemaining
    case tokensToday
    case iconOnly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .quotaRemaining: return "Codex quota remaining"
        case .tokensToday: return "Reported tokens today"
        case .iconOnly: return "Icon only"
        }
    }
}

enum UsagePeriod: Equatable {
    case today
    case monthToDate
    case throughYesterday
    case recentRate

    var label: String {
        switch self {
        case .today: return "Today"
        case .monthToDate: return "Month to date"
        case .throughYesterday: return "Month through yesterday"
        case .recentRate: return "Current 5-minute rate"
        }
    }

    var contributesToDailyTotal: Bool { self == .today }
}

enum ProviderState: Equatable {
    case waiting
    case loading
    case available
    case unconfigured
    case unavailable(String)
}

struct ProviderUsage {
    let id: ProviderID
    var tokens: Int64?
    var spendUSD: Double?
    var period: UsagePeriod
    var secondaryMetric: String?
    var isPartial = false
    var state: ProviderState = .waiting

    static func waiting(_ id: ProviderID) -> ProviderUsage {
        ProviderUsage(id: id, tokens: nil, spendUSD: nil, period: .today, secondaryMetric: nil)
    }
}

struct CodexSnapshot {
    let windows: [QuotaWindow]
    let tokensToday: Int64?
}

struct OpenRouterSnapshot {
    let tokensToday: Int64
    let spendTodayUSD: Double
    let isPartial: Bool
}

struct ProviderFetchResult {
    let usage: ProviderUsage
    let quotaWindows: [QuotaWindow]
}

enum ProviderAdapterError: LocalizedError {
    case notConfigured
    case invalidConfiguration(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "This provider is not configured."
        case .invalidConfiguration(let message), .unsupported(let message): return message
        }
    }
}

protocol UsageProviderAdapter {
    var id: ProviderID { get }
    func fetch(completion: @escaping (Result<ProviderFetchResult, Error>) -> Void)
}
