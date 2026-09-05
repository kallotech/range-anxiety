import Foundation

enum ClaudeUsageCaptureSetupError: LocalizedError {
    case launcherMissing
    case invalidSettings

    var errorDescription: String? {
        switch self {
        case .launcherMissing: return "The bundled ra launcher could not be found. Rebuild or reinstall RangeAnxiety."
        case .invalidSettings: return "Claude's settings.json is not a valid JSON object. It was left unchanged."
        }
    }
}

@MainActor
final class ClaudeUsageCaptureController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?

    private let manager: FileManager
    private let claudeDirectory: URL
    private let backupURL: URL
    private let launcherURL: URL
    private let marker = "claude-statusline --out"

    init(
        manager: FileManager = .default,
        claudeDirectory: URL? = nil,
        supportDirectory: URL? = nil,
        launcherURL: URL? = nil
    ) {
        self.manager = manager
        if let claudeDirectory {
            self.claudeDirectory = claudeDirectory
        } else if let configured = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
            self.claudeDirectory = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            self.claudeDirectory = manager.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
        }
        let support = supportDirectory ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RangeAnxiety", isDirectory: true)
        self.backupURL = support.appendingPathComponent("claude-statusline-backup.json")
        self.launcherURL = launcherURL ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/ra")
        reload()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try install() } else { try uninstall() }
            statusMessage = nil
            reload()
        } catch {
            statusMessage = error.localizedDescription
            reload()
        }
    }

    func reload() {
        guard let settings = try? readSettings(),
              let statusLine = settings["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String else {
            isEnabled = false
            return
        }
        isEnabled = command.contains(marker)
    }

    private var settingsURL: URL { claudeDirectory.appendingPathComponent("settings.json") }

    private func install() throws {
        var settings = try readSettings()
        if let current = settings["statusLine"] as? [String: Any],
           (current["command"] as? String)?.contains(marker) == true { return }

        guard manager.isExecutableFile(atPath: launcherURL.path) else { throw ClaudeUsageCaptureSetupError.launcherMissing }

        let existingStatusLine = settings["statusLine"]
        let backup: [String: Any] = [
            "hadStatusLine": existingStatusLine != nil,
            "statusLine": existingStatusLine ?? NSNull()
        ]
        try writeJSON(backup, to: backupURL)

        var command = "\(shellQuote(launcherURL.path)) claude-statusline --out \(shellQuote(ClaudeUsageCapturePaths.captureURL.path))"
        if let existing = existingStatusLine as? [String: Any],
           existing["type"] as? String == "command",
           let chained = existing["command"] as? String, !chained.isEmpty {
            command += " --chain-base64 \(shellQuote(Data(chained.utf8).base64EncodedString()))"
        }
        var replacement = existingStatusLine as? [String: Any] ?? [:]
        replacement["type"] = "command"
        replacement["command"] = command
        if replacement["refreshInterval"] == nil { replacement["refreshInterval"] = 60 }
        settings["statusLine"] = replacement
        try writeJSON(settings, to: settingsURL)
    }

    private func uninstall() throws {
        var settings = try readSettings()
        guard let current = settings["statusLine"] as? [String: Any],
              (current["command"] as? String)?.contains(marker) == true else { return }

        if let backupData = try? Data(contentsOf: backupURL),
           let backup = try? JSONSerialization.jsonObject(with: backupData) as? [String: Any],
           backup["hadStatusLine"] as? Bool == true,
           let original = backup["statusLine"], !(original is NSNull) {
            settings["statusLine"] = original
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try writeJSON(settings, to: settingsURL)
        if manager.fileExists(atPath: backupURL.path) { try manager.removeItem(at: backupURL) }
    }

    private func readSettings() throws -> [String: Any] {
        guard manager.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageCaptureSetupError.invalidSettings
        }
        return object
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try manager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
