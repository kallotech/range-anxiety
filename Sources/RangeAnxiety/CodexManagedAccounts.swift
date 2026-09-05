import AppKit
import Foundation

struct ManagedCodexSnapshot {
    let isSignedIn: Bool
    let planType: String?
    let windows: [QuotaWindow]
}

enum ManagedCodexError: LocalizedError {
    case codexNotFound
    case launchFailed(String)
    case invalidResponse
    case timedOut
    case cancelled
    case server(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "Codex was not found on this Mac."
        case .launchFailed(let message): return "Could not start Codex: \(message)"
        case .invalidResponse: return "Codex returned an unexpected account response."
        case .timedOut: return "Codex account setup timed out."
        case .cancelled: return "Codex account setup was cancelled."
        case .server(let message): return message
        }
    }
}

enum CodexExecutableLocator {
    static func find() -> String? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let override = environment["CODEX_BINARY_PATH"], !override.isEmpty { candidates.append(override) }
        candidates.append(contentsOf: [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ])
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

final class CodexManagedAccountReader {
    private let profileURL: URL

    init(profileURL: URL) { self.profileURL = profileURL }

    func read(completion: @escaping (Result<ManagedCodexSnapshot, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result = self.readBlocking()
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func readBlocking() -> Result<ManagedCodexSnapshot, Error> {
        guard let codex = CodexExecutableLocator.find() else { return .failure(ManagedCodexError.codexNotFound) }
        let process = Process()
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: codex)
        process.arguments = ["app-server", "--stdio"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = profileURL.path
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
            try Self.write(["method": "initialize", "id": 1, "params": ["clientInfo": ["name": "rangeanxiety", "title": "RangeAnxiety", "version": "0.7.0"]]], to: input)
            try Self.write(["method": "initialized", "params": [:]], to: input)
            try Self.write(["method": "account/read", "id": 2, "params": ["refreshToken": false]], to: input)
            try Self.write(["method": "account/rateLimits/read", "id": 3], to: input)

            let deadline = Date().addingTimeInterval(15)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15) {
                if process.isRunning { process.terminate() }
            }
            var account: [String: Any]?
            var windows: [QuotaWindow] = []
            var receivedAccount = false
            var receivedLimits = false
            while Date() < deadline, let line = try Self.readLine(from: output.fileHandleForReading) {
                guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = (message["id"] as? NSNumber)?.intValue else { continue }
                if id == 2 {
                    receivedAccount = true
                    account = (message["result"] as? [String: Any])?["account"] as? [String: Any]
                } else if id == 3 {
                    receivedLimits = true
                    windows = Self.parseWindows(message)
                }
                if receivedAccount && receivedLimits { break }
            }
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            guard receivedAccount else { return .failure(ManagedCodexError.timedOut) }
            return .success(ManagedCodexSnapshot(
                isSignedIn: account != nil,
                planType: account?["planType"] as? String,
                windows: windows
            ))
        } catch {
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            return .failure(ManagedCodexError.launchFailed(error.localizedDescription))
        }
    }

    static func write(_ object: [String: Any], to pipe: Pipe) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        pipe.fileHandleForWriting.write(data)
    }

    static func readLine(from handle: FileHandle) throws -> Data? {
        var data = Data()
        while true {
            let byte = try handle.read(upToCount: 1) ?? Data()
            if byte.isEmpty { return data.isEmpty ? nil : data }
            if byte[0] == 0x0A { return data }
            data.append(byte)
        }
    }

    static func parseWindows(_ message: [String: Any]) -> [QuotaWindow] {
        guard let result = message["result"] as? [String: Any] else { return [] }
        let buckets: [[String: Any]]
        if let byID = result["rateLimitsByLimitId"] as? [String: [String: Any]], !byID.isEmpty {
            buckets = byID.sorted(by: { $0.key < $1.key }).map(\.value)
        } else if let rateLimits = result["rateLimits"] as? [String: Any] {
            buckets = [rateLimits]
        } else { return [] }

        var windows: [QuotaWindow] = []
        for bucket in buckets {
            let bucketID = bucket["limitId"] as? String ?? "codex"
            let bucketName = bucket["limitName"] as? String
            for (suffix, value) in [("primary", bucket["primary"]), ("secondary", bucket["secondary"])] {
                guard let raw = value as? [String: Any],
                      let used = (raw["usedPercent"] as? NSNumber)?.doubleValue,
                      let minutes = (raw["windowDurationMins"] as? NSNumber)?.intValue else { continue }
                let reset = (raw["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                let base = bucketName?.isEmpty == false ? bucketName! : durationTitle(minutes)
                let title = buckets.count > 1 ? base : durationTitle(minutes)
                windows.append(QuotaWindow(id: "\(bucketID)-\(suffix)", title: title, usedPercent: used, durationMinutes: minutes, resetsAt: reset))
            }
        }
        return windows
    }

    private static func durationTitle(_ minutes: Int) -> String {
        switch minutes {
        case 300: return "5-hour limit"
        case 10_080: return "Weekly limit"
        case let value where value.isMultiple(of: 1_440): return "\(value / 1_440)-day limit"
        case let value where value.isMultiple(of: 60): return "\(value / 60)-hour limit"
        default: return "\(minutes)-minute limit"
        }
    }
}

final class CodexLoginCoordinator {
    private let profileURL: URL
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = Data()
    private var completion: ((Result<ManagedCodexSnapshot, Error>) -> Void)?
    private var finished = false

    init(profileURL: URL) { self.profileURL = profileURL }

    func start(completion: @escaping (Result<ManagedCodexSnapshot, Error>) -> Void) {
        guard let codex = CodexExecutableLocator.find() else {
            completion(.failure(ManagedCodexError.codexNotFound)); return
        }
        self.completion = completion
        let process = Process(), input = Pipe(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: codex)
        process.arguments = ["app-server", "--stdio"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = profileURL.path
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        self.process = process
        self.input = input
        self.output = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in self?.ingest(handle.availableData) }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.finished else { return }
                self.finish(.failure(ManagedCodexError.server("Codex closed before sign-in completed.")))
            }
        }
        do {
            try process.run()
            try CodexManagedAccountReader.write(["method": "initialize", "id": 1, "params": ["clientInfo": ["name": "rangeanxiety", "title": "RangeAnxiety", "version": "0.7.0"]]], to: input)
            try CodexManagedAccountReader.write(["method": "initialized", "params": [:]], to: input)
            try CodexManagedAccountReader.write(["method": "account/login/start", "id": 2, "params": ["type": "chatgpt", "useHostedLoginSuccessPage": true, "appBrand": "codex"]], to: input)
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
                guard let self, !self.finished else { return }
                self.finish(.failure(ManagedCodexError.timedOut))
            }
        } catch {
            finish(.failure(ManagedCodexError.launchFailed(error.localizedDescription)))
        }
    }

    func cancel() { finish(.failure(ManagedCodexError.cancelled)) }

    private func ingest(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            DispatchQueue.main.async { [weak self] in self?.handle(message) }
        }
    }

    private func handle(_ message: [String: Any]) {
        if let id = (message["id"] as? NSNumber)?.intValue, id == 2 {
            if let error = message["error"] as? [String: Any] {
                finish(.failure(ManagedCodexError.server(error["message"] as? String ?? "Could not start sign-in.")))
                return
            }
            if let result = message["result"] as? [String: Any],
               let value = result["authUrl"] as? String, let url = URL(string: value) {
                NSWorkspace.shared.open(url)
            }
        }
        if message["method"] as? String == "account/login/completed",
           let params = message["params"] as? [String: Any] {
            guard params["success"] as? Bool == true else {
                finish(.failure(ManagedCodexError.server(params["error"] as? String ?? "Sign-in did not complete.")))
                return
            }
            guard let input else { finish(.failure(ManagedCodexError.invalidResponse)); return }
            try? CodexManagedAccountReader.write(["method": "account/read", "id": 3, "params": ["refreshToken": false]], to: input)
            try? CodexManagedAccountReader.write(["method": "account/rateLimits/read", "id": 4], to: input)
        }
        if let id = (message["id"] as? NSNumber)?.intValue, id == 3,
           let result = message["result"] as? [String: Any] {
            let account = result["account"] as? [String: Any]
            finish(.success(ManagedCodexSnapshot(isSignedIn: account != nil, planType: account?["planType"] as? String, windows: [])))
        }
    }

    private func finish(_ result: Result<ManagedCodexSnapshot, Error>) {
        guard !finished else { return }
        finished = true
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        if process?.isRunning == true { process?.terminate() }
        let callback = completion
        completion = nil
        callback?(result)
    }
}
