import Foundation

enum Provider: String, Codable { case codex, claude }
struct Account: Codable {
    let id: UUID
    let nickname: String
    let provider: Provider
    let isActive: Bool
    let createdAt: Date
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data(("ra: \(message)\n").utf8))
    exit(code)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    fail("use 'ra list', 'ra codex', or 'ra claude'")
}
let home = FileManager.default.homeDirectoryForCurrentUser
let accountsURL = ProcessInfo.processInfo.environment["RANGE_ANXIETY_ACCOUNTS_PATH"].map(URL.init(fileURLWithPath:))
    ?? home.appendingPathComponent("Library/Application Support/RangeAnxiety/accounts.json")
let data: Data
do { data = try Data(contentsOf: accountsURL) }
catch { fail("no managed accounts found; add one in RangeAnxiety Settings") }
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let accounts: [Account]
do { accounts = try decoder.decode([Account].self, from: data) }
catch { fail("the managed account file could not be read") }

if command == "list" {
    for account in accounts {
        print("\(account.provider.rawValue)\t\(account.isActive ? "active" : "inactive")\t\(account.nickname)")
    }
    exit(0)
}
guard let provider = Provider(rawValue: command) else { fail("unknown command '\(command)'") }
guard let account = accounts.first(where: { $0.provider == provider && $0.isActive }) else {
    fail("no active \(provider.rawValue) account; activate one in RangeAnxiety Settings")
}
let profile = home.appendingPathComponent("Library/Application Support/RangeAnxiety/Accounts")
    .appendingPathComponent(account.id.uuidString).appendingPathComponent(provider.rawValue)
do {
    try FileManager.default.createDirectory(
        at: profile,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
} catch {
    fail("could not prepare the managed profile: \(error.localizedDescription)")
}
var candidates: [String]
switch provider {
case .codex:
    candidates = [
        "/Applications/ChatGPT.app/Contents/Resources/codex",
        "/Applications/Codex.app/Contents/Resources/codex",
        "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
    ]
case .claude:
    candidates = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
}
if let path = ProcessInfo.processInfo.environment["PATH"] {
    candidates += path.split(separator: ":").map { "\($0)/\(provider.rawValue)" }
}
guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
    fail("\(provider.rawValue) CLI is not installed")
}
let process = Process()
process.executableURL = URL(fileURLWithPath: executable)
process.arguments = Array(arguments.dropFirst())
var environment = ProcessInfo.processInfo.environment
environment[provider == .codex ? "CODEX_HOME" : "CLAUDE_CONFIG_DIR"] = profile.path
process.environment = environment
process.standardInput = FileHandle.standardInput
process.standardOutput = FileHandle.standardOutput
process.standardError = FileHandle.standardError
do { try process.run(); process.waitUntilExit(); exit(process.terminationStatus) }
catch { fail("could not start \(provider.rawValue): \(error.localizedDescription)") }
