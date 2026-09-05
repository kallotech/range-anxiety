import AppKit
import Foundation

enum ManagedCLIProvider: String, Codable, CaseIterable, Identifiable {
    case codex
    case claude

    var id: String { rawValue }
    var displayName: String { self == .codex ? "Codex" : "Claude Code" }
    var environmentKey: String { self == .codex ? "CODEX_HOME" : "CLAUDE_CONFIG_DIR" }
}

struct ManagedAccount: Codable, Identifiable, Equatable {
    let id: UUID
    var nickname: String
    let provider: ManagedCLIProvider
    var isActive: Bool
    let createdAt: Date
}

enum ManagedAccountAuthState: Equatable {
    case unknown
    case checking
    case signedOut
    case signingIn
    case signedIn(plan: String?)
    case unavailable(String)

    var label: String {
        switch self {
        case .unknown: return "Not checked"
        case .checking: return "Checking…"
        case .signedOut: return "Sign in required"
        case .signingIn: return "Complete sign-in in your browser"
        case .signedIn(let plan): return plan.map { "Signed in · \($0.capitalized)" } ?? "Signed in"
        case .unavailable(let message): return message
        }
    }
}

enum ManagedAccountStoreError: LocalizedError {
    case invalidName
    case unsupportedProvider

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Enter a short name for this account."
        case .unsupportedProvider: return "Claude Code account sign-in will be enabled after the Claude CLI is installed."
        }
    }
}

final class ManagedAccountStore {
    static let shared = ManagedAccountStore()

    let rootURL: URL
    private let accountsURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootURL = support.appendingPathComponent("RangeAnxiety/Accounts", isDirectory: true)
        accountsURL = support.appendingPathComponent("RangeAnxiety/accounts.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> [ManagedAccount] {
        guard FileManager.default.fileExists(atPath: accountsURL.path) else { return [] }
        return try decoder.decode([ManagedAccount].self, from: Data(contentsOf: accountsURL))
    }

    func save(_ accounts: [ManagedAccount]) throws {
        let manager = FileManager.default
        let parent = accountsURL.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try encoder.encode(accounts).write(to: accountsURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: accountsURL.path)
    }

    func profileURL(for account: ManagedAccount) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = rootURL.appendingPathComponent(account.id.uuidString, isDirectory: true)
            .appendingPathComponent(account.provider.rawValue, isDirectory: true)
        try manager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }

    func removeProfile(for account: ManagedAccount) throws {
        let accountURL = rootURL.appendingPathComponent(account.id.uuidString, isDirectory: true)
        let standardizedRoot = rootURL.standardizedFileURL.path + "/"
        guard accountURL.standardizedFileURL.path.hasPrefix(standardizedRoot) else { return }
        if FileManager.default.fileExists(atPath: accountURL.path) {
            try FileManager.default.removeItem(at: accountURL)
        }
    }
}

@MainActor
final class ManagedAccountsController: ObservableObject {
    @Published private(set) var accounts: [ManagedAccount] = []
    @Published private(set) var authStates: [UUID: ManagedAccountAuthState] = [:]
    @Published private(set) var windows: [UUID: [QuotaWindow]] = [:]
    @Published private(set) var errorMessage: String?

    private let store: ManagedAccountStore
    private var loginCoordinators: [UUID: CodexLoginCoordinator] = [:]

    init(store: ManagedAccountStore = .shared) {
        self.store = store
        do {
            accounts = try store.load()
        } catch {
            errorMessage = "Could not read managed accounts: \(error.localizedDescription)"
        }
        refreshAll()
    }

    func add(provider: ManagedCLIProvider, nickname rawNickname: String) {
        let nickname = rawNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty, nickname.count <= 48 else {
            errorMessage = ManagedAccountStoreError.invalidName.localizedDescription
            return
        }
        guard provider == .codex else {
            errorMessage = ManagedAccountStoreError.unsupportedProvider.localizedDescription
            return
        }
        var account = ManagedAccount(id: UUID(), nickname: nickname, provider: provider, isActive: false, createdAt: Date())
        if !accounts.contains(where: { $0.provider == provider && $0.isActive }) { account.isActive = true }
        do {
            _ = try store.profileURL(for: account)
            accounts.append(account)
            try persist()
            errorMessage = nil
            signIn(account)
        } catch {
            errorMessage = "Could not create the account profile: \(error.localizedDescription)"
        }
    }

    func signIn(_ account: ManagedAccount) {
        guard account.provider == .codex else { return }
        do {
            let profileURL = try store.profileURL(for: account)
            authStates[account.id] = .signingIn
            let coordinator = CodexLoginCoordinator(profileURL: profileURL)
            loginCoordinators[account.id] = coordinator
            coordinator.start { [weak self] result in
                guard let self else { return }
                self.loginCoordinators[account.id] = nil
                switch result {
                case .success(let snapshot):
                    self.authStates[account.id] = snapshot.isSignedIn ? .signedIn(plan: snapshot.planType) : .signedOut
                    self.windows[account.id] = snapshot.windows
                    self.errorMessage = nil
                    self.refresh(account)
                case .failure(let error):
                    self.authStates[account.id] = .unavailable(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                }
            }
        } catch {
            authStates[account.id] = .unavailable(error.localizedDescription)
        }
    }

    func activate(_ account: ManagedAccount) {
        for index in accounts.indices where accounts[index].provider == account.provider {
            accounts[index].isActive = accounts[index].id == account.id
        }
        do { try persist(); errorMessage = nil }
        catch { errorMessage = "Could not activate the account: \(error.localizedDescription)" }
    }

    func remove(_ account: ManagedAccount) {
        loginCoordinators[account.id]?.cancel()
        loginCoordinators[account.id] = nil
        do {
            try store.removeProfile(for: account)
            accounts.removeAll { $0.id == account.id }
            authStates[account.id] = nil
            windows[account.id] = nil
            if !accounts.contains(where: { $0.provider == account.provider && $0.isActive }),
               let replacement = accounts.firstIndex(where: { $0.provider == account.provider }) {
                accounts[replacement].isActive = true
            }
            try persist()
            errorMessage = nil
        } catch {
            errorMessage = "Could not remove the managed profile: \(error.localizedDescription)"
        }
    }

    func refreshAll() {
        for account in accounts { refresh(account) }
    }

    func refresh(_ account: ManagedAccount) {
        guard account.provider == .codex, loginCoordinators[account.id] == nil else { return }
        authStates[account.id] = .checking
        do {
            let profileURL = try store.profileURL(for: account)
            CodexManagedAccountReader(profileURL: profileURL).read { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let snapshot):
                    self.authStates[account.id] = snapshot.isSignedIn ? .signedIn(plan: snapshot.planType) : .signedOut
                    self.windows[account.id] = snapshot.windows
                case .failure(let error):
                    self.authStates[account.id] = .unavailable(error.localizedDescription)
                }
            }
        } catch {
            authStates[account.id] = .unavailable(error.localizedDescription)
        }
    }

    private func persist() throws { try store.save(accounts) }
}
