import Foundation

enum ConnectorAvailability: Equatable {
    case supported
    case unavailable(String)
}

struct ProviderDescriptor: Identifiable {
    let id: ProviderID
    let name: String
    let systemImage: String
    let detail: String
    let credentialLabel: String?
    let auxiliaryLabel: String?
    let auxiliaryRequired: Bool
    let helpTitle: String?
    let helpURL: URL?
    let availability: ConnectorAvailability

    var requiresCredential: Bool { credentialLabel != nil }
}

enum ProviderCatalog {
    static let providers: [ProviderDescriptor] = [
        ProviderDescriptor(
            id: .codex,
            name: "Codex",
            systemImage: "terminal",
            detail: "Shows Codex quota windows using the login already available on this Mac. This app stores no Codex password or token.",
            credentialLabel: nil,
            auxiliaryLabel: nil,
            auxiliaryRequired: false,
            helpTitle: nil,
            helpURL: nil,
            availability: .supported
        ),
        ProviderDescriptor(
            id: .claudeCode,
            name: "Claude Code",
            systemImage: "sparkles",
            detail: "Shows the 5-hour and 7-day subscription limits Claude Code provides to its status line. RangeAnxiety captures only percentages and reset times, never OAuth credentials.",
            credentialLabel: nil,
            auxiliaryLabel: nil,
            auxiliaryRequired: false,
            helpTitle: "Claude status-line documentation",
            helpURL: URL(string: "https://code.claude.com/docs/en/statusline"),
            availability: .supported
        ),
        ProviderDescriptor(
            id: .openRouter,
            name: "OpenRouter",
            systemImage: "arrow.triangle.branch",
            detail: "Daily tokens and USD spend from OpenRouter analytics.",
            credentialLabel: "Management key",
            auxiliaryLabel: nil,
            auxiliaryRequired: false,
            helpTitle: "Create management key",
            helpURL: URL(string: "https://openrouter.ai/settings/management-keys"),
            availability: .supported
        ),
        ProviderDescriptor(
            id: .openAI,
            name: "OpenAI API",
            systemImage: "sparkles",
            detail: "Daily organization tokens and costs. Requires an organization Admin API key, not a normal project key.",
            credentialLabel: "Admin API key",
            auxiliaryLabel: nil,
            auxiliaryRequired: false,
            helpTitle: "Open API keys",
            helpURL: URL(string: "https://platform.openai.com/settings/organization/admin-keys"),
            availability: .supported
        ),
        ProviderDescriptor(
            id: .anthropic,
            name: "Anthropic",
            systemImage: "a.circle",
            detail: "Daily organization tokens and costs. Requires an Anthropic Admin API key.",
            credentialLabel: "Admin API key",
            auxiliaryLabel: nil,
            auxiliaryRequired: false,
            helpTitle: "Open Anthropic settings",
            helpURL: URL(string: "https://console.anthropic.com/settings/admin-keys"),
            availability: .supported
        ),
        ProviderDescriptor(
            id: .xAI,
            name: "xAI",
            systemImage: "xmark",
            detail: "Month-to-date team spend from the xAI Management API.",
            credentialLabel: "Management key",
            auxiliaryLabel: "Team ID",
            auxiliaryRequired: true,
            helpTitle: "Open xAI Console",
            helpURL: URL(string: "https://console.x.ai/"),
            availability: .supported
        ),
        ProviderDescriptor(
            id: .mistral,
            name: "Mistral AI",
            systemImage: "wind",
            detail: "Month-to-date organization usage from Mistral's Admin API.",
            credentialLabel: "Admin API key",
            auxiliaryLabel: nil,
            auxiliaryRequired: false,
            helpTitle: "Open Mistral Console",
            helpURL: URL(string: "https://console.mistral.ai/"),
            availability: .supported
        ),
        ProviderDescriptor(
            id: .together,
            name: "Together AI",
            systemImage: "square.stack.3d.up",
            detail: "Month-to-date spend through yesterday. Together finalizes daily billing after the day closes.",
            credentialLabel: "API key",
            auxiliaryLabel: "Organization ID (optional)",
            auxiliaryRequired: false,
            helpTitle: "Open Together settings",
            helpURL: URL(string: "https://api.together.ai/settings/api-keys"),
            availability: .supported
        ),
        ProviderDescriptor(
            id: .fireworks,
            name: "Fireworks AI",
            systemImage: "sparkler",
            detail: "Month-to-date account spend from Fireworks billing summaries.",
            credentialLabel: "API key",
            auxiliaryLabel: "Account ID",
            auxiliaryRequired: true,
            helpTitle: "Open Fireworks settings",
            helpURL: URL(string: "https://fireworks.ai/account/api-keys"),
            availability: .supported
        ),
        ProviderDescriptor(
            id: .groq,
            name: "GroqCloud Enterprise",
            systemImage: "bolt",
            detail: "Current five-minute token rate from Groq's Prometheus API. This API is available on Enterprise plans.",
            credentialLabel: "API key",
            auxiliaryLabel: nil,
            auxiliaryRequired: false,
            helpTitle: "Open Groq keys",
            helpURL: URL(string: "https://console.groq.com/keys"),
            availability: .supported
        ),
        ProviderDescriptor(
            id: .gemini,
            name: "Google Gemini",
            systemImage: "diamond",
            detail: "Google does not expose account-wide usage to a normal Gemini API key.",
            credentialLabel: nil,
            auxiliaryLabel: nil,
            auxiliaryRequired: false,
            helpTitle: nil,
            helpURL: nil,
            availability: .unavailable("Needs a future Google Cloud Monitoring connector and Google sign-in.")
        ),
        ProviderDescriptor(
            id: .deepSeek,
            name: "DeepSeek",
            systemImage: "waveform.path.ecg",
            detail: "DeepSeek does not currently publish an account-wide usage reporting API.",
            credentialLabel: nil,
            auxiliaryLabel: nil,
            auxiliaryRequired: false,
            helpTitle: nil,
            helpURL: nil,
            availability: .unavailable("No safe reporting connector is currently available.")
        ),
        ProviderDescriptor(
            id: .azureOpenAI,
            name: "Azure OpenAI",
            systemImage: "cloud",
            detail: "Azure usage is reported through Azure Monitor and Cost Management, not an ordinary model API key.",
            credentialLabel: nil,
            auxiliaryLabel: nil,
            auxiliaryRequired: false,
            helpTitle: nil,
            helpURL: nil,
            availability: .unavailable("Needs a future Microsoft sign-in and Azure subscription selector.")
        )
    ]

    static func descriptor(for id: ProviderID) -> ProviderDescriptor {
        providers.first { $0.id == id }!
    }
}

extension ProviderID {
    var descriptor: ProviderDescriptor { ProviderCatalog.descriptor(for: self) }
    var displayName: String { descriptor.name }
    var systemImage: String { descriptor.systemImage }
}
