import Foundation

enum CLIHealthState: Equatable {
    case checking
    case healthy
    case needsAttention(String)
    case notInstalled
}

struct CLIToolHealth: Identifiable, Equatable {
    let id: ManagedCLIProvider
    var state: CLIHealthState
    var executablePath: String?
    var installedVersion: String?
    var latestVersion: String?
    var authSummary: String?
    var installationSource: String?
    var updateGuidance: String?

    static func checking(_ provider: ManagedCLIProvider) -> CLIToolHealth {
        CLIToolHealth(id: provider, state: .checking)
    }
}

@MainActor
final class CLIHealthController: ObservableObject {
    @Published private(set) var tools = Dictionary(
        uniqueKeysWithValues: ManagedCLIProvider.allCases.map { ($0, CLIToolHealth.checking($0)) }
    )
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?

    init() { refresh() }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        for provider in ManagedCLIProvider.allCases { tools[provider] = .checking(provider) }
        let group = DispatchGroup()
        let lock = NSLock()
        var values: [ManagedCLIProvider: CLIToolHealth] = [:]
        for provider in ManagedCLIProvider.allCases {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let value = Self.inspect(provider)
                lock.lock(); values[provider] = value; lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.tools = values
            self.isRefreshing = false
            self.lastUpdated = Date()
        }
    }

    func health(for provider: ManagedCLIProvider) -> CLIToolHealth {
        tools[provider] ?? .checking(provider)
    }

    nonisolated private static func inspect(_ provider: ManagedCLIProvider) -> CLIToolHealth {
        guard let path = executablePath(for: provider) else {
            return CLIToolHealth(id: provider, state: .notInstalled, updateGuidance: installGuidance(for: provider))
        }
        let version = run(path, arguments: ["--version"]).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let auth: CommandResult
        switch provider {
        case .codex: auth = run(path, arguments: ["login", "status"])
        case .claude: auth = run(path, arguments: ["auth", "status", "--json"])
        }
        let authText = auth.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let state: CLIHealthState = auth.status == 0 ? .healthy : .needsAttention("Sign in again")
        let latestVersion = fetchLatestVersion(for: provider)
        return CLIToolHealth(
            id: provider,
            state: state,
            executablePath: path,
            installedVersion: version.isEmpty ? nil : version,
            latestVersion: latestVersion,
            authSummary: auth.status == 0 ? (authText.isEmpty ? "Authentication available" : firstSafeLine(authText)) : "Authentication needs attention",
            installationSource: source(for: path),
            updateGuidance: updateGuidance(for: provider, path: path)
        )
    }

    private struct CommandResult { let status: Int32; let output: String }

    nonisolated private static func run(_ path: String, arguments: [String]) -> CommandResult {
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile() + errors.fileHandleForReading.readDataToEndOfFile()
            return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        } catch {
            return CommandResult(status: 1, output: error.localizedDescription)
        }
    }

    nonisolated private static func executablePath(for provider: ManagedCLIProvider) -> String? {
        let name = provider.rawValue
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if provider == .codex {
            candidates += ["/Applications/ChatGPT.app/Contents/Resources/codex", "/Applications/Codex.app/Contents/Resources/codex"]
        }
        candidates += ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
        if let path = environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/\(name)" }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated private static func source(for path: String) -> String {
        if path.hasPrefix("/Applications/ChatGPT.app") { return "Bundled with ChatGPT" }
        if path.hasPrefix("/Applications/Codex.app") { return "Bundled with Codex" }
        if path.hasPrefix("/opt/homebrew") || path.hasPrefix("/usr/local") { return "Homebrew or local CLI" }
        return "Custom PATH"
    }

    nonisolated private static func updateGuidance(for provider: ManagedCLIProvider, path: String) -> String {
        if path.hasPrefix("/Applications/ChatGPT.app") { return "Update ChatGPT to update its bundled Codex CLI." }
        if path.hasPrefix("/Applications/Codex.app") { return "Update the Codex app to update its bundled CLI." }
        switch provider {
        case .codex: return "Run ‘codex update’, or upgrade the package manager that installed Codex."
        case .claude: return "Use Claude Code’s installer or the package manager that installed it."
        }
    }

    nonisolated private static func installGuidance(for provider: ManagedCLIProvider) -> String {
        provider == .codex ? "Install Codex or the ChatGPT desktop app." : "Install Claude Code to enable account health and managed profiles."
    }

    nonisolated private static func fetchLatestVersion(for provider: ManagedCLIProvider) -> String? {
        let urlString: String
        switch provider {
        case .codex: urlString = "https://api.github.com/repos/openai/codex/releases/latest"
        case .claude: urlString = "https://registry.npmjs.org/@anthropic-ai/claude-code/latest"
        }
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue("RangeAnxiety/0.7", forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            responseData = data
            semaphore.signal()
        }.resume()
        guard semaphore.wait(timeout: .now() + 7) == .success,
              let responseData,
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else { return nil }
        let raw: String?
        switch provider {
        case .codex: raw = json["tag_name"] as? String
        case .claude: raw = json["version"] as? String
        }
        guard var value = raw else { return nil }
        for prefix in ["rust-v", "v"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            break
        }
        return value
    }

    nonisolated private static func firstSafeLine(_ value: String) -> String {
        let line = value.split(whereSeparator: \.isNewline).first.map(String.init) ?? value
        if line.contains("@") { return "Signed in" }
        return String(line.prefix(120))
    }
}
