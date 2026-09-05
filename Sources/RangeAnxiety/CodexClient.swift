import Foundation

enum CodexClientError: LocalizedError {
    case codexNotFound
    case launchFailed(String)
    case timedOut
    case connectionClosed
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "Codex was not found on this Mac."
        case .launchFailed(let message): return "Could not start Codex: \(message)"
        case .timedOut: return "Codex did not respond in time."
        case .connectionClosed: return "The Codex connection closed unexpectedly."
        case .server(let message): return message
        case .invalidResponse: return "Codex returned an unexpected response."
        }
    }
}

final class CodexResponseCollector {
    private let lock = NSLock()
    private var buffer = Data()
    private var quotaResult: Result<[QuotaWindow], Error>?
    private var usageResult: Result<Int64?, Error>?
    private var storedResult: Result<CodexSnapshot, Error>?
    private let today: String
    let semaphore = DispatchSemaphore(value: 0)

    init(today: String) { self.today = today }

    var result: Result<CodexSnapshot, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }

    func ingest(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard storedResult == nil else { return }

        if data.isEmpty {
            finishFromAvailableResponsesLocked(fallback: CodexClientError.connectionClosed)
            return
        }

        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)),
                  let message = object as? [String: Any],
                  let id = (message["id"] as? NSNumber)?.intValue else { continue }

            switch id {
            case 2:
                quotaResult = parseResult(message, parser: Self.parseWindows)
            case 3:
                usageResult = parseResult(message) { try Self.parseTokensToday(from: $0, today: self.today) }
            default:
                continue
            }

            finishIfReadyLocked()
            if storedResult != nil { return }
        }
    }

    func completeOnTimeout() {
        lock.lock()
        defer { lock.unlock() }
        guard storedResult == nil else { return }
        finishFromAvailableResponsesLocked(fallback: CodexClientError.timedOut)
    }

    func completeIfNeeded(_ result: Result<CodexSnapshot, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard storedResult == nil else { return }
        completeLocked(result)
    }

    private func parseResult<T>(
        _ message: [String: Any],
        parser: ([String: Any]) throws -> T
    ) -> Result<T, Error> {
        if let error = message["error"] as? [String: Any] {
            return .failure(CodexClientError.server(error["message"] as? String ?? "Codex could not read usage."))
        }
        do { return .success(try parser(message)) }
        catch { return .failure(error) }
    }

    private func finishIfReadyLocked() {
        guard quotaResult != nil, usageResult != nil else { return }
        finishFromAvailableResponsesLocked(fallback: CodexClientError.invalidResponse)
    }

    private func finishFromAvailableResponsesLocked(fallback: Error) {
        guard let quotaResult else {
            completeLocked(.failure(fallback))
            return
        }

        switch quotaResult {
        case .failure(let error):
            completeLocked(.failure(error))
        case .success(let windows):
            let tokens: Int64?
            if case .success(let value) = usageResult { tokens = value } else { tokens = nil }
            completeLocked(.success(CodexSnapshot(windows: windows, tokensToday: tokens)))
        }
    }

    private func completeLocked(_ result: Result<CodexSnapshot, Error>) {
        storedResult = result
        semaphore.signal()
    }

    static func parseWindows(from message: [String: Any]) throws -> [QuotaWindow] {
        let windows = CodexManagedAccountReader.parseWindows(message)
        guard !windows.isEmpty else { throw CodexClientError.invalidResponse }
        return windows
    }

    static func parseTokensToday(from message: [String: Any], today: String) throws -> Int64? {
        guard let result = message["result"] as? [String: Any] else {
            throw CodexClientError.invalidResponse
        }
        if result["dailyUsageBuckets"] is NSNull || result["dailyUsageBuckets"] == nil { return nil }
        guard let buckets = result["dailyUsageBuckets"] as? [[String: Any]] else {
            throw CodexClientError.invalidResponse
        }
        return buckets
            .filter { $0["startDate"] as? String == today }
            .compactMap { ($0["tokens"] as? NSNumber)?.int64Value }
            .reduce(0, +)
    }

    private static func parseWindow(_ value: Any?, id: String) -> QuotaWindow? {
        guard let dictionary = value as? [String: Any],
              let usedPercent = (dictionary["usedPercent"] as? NSNumber)?.doubleValue,
              let durationMinutes = (dictionary["windowDurationMins"] as? NSNumber)?.intValue else { return nil }
        let resetsAt = (dictionary["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return QuotaWindow(
            id: id,
            title: windowTitle(minutes: durationMinutes, fallback: id),
            usedPercent: usedPercent,
            durationMinutes: durationMinutes,
            resetsAt: resetsAt
        )
    }

    private static func windowTitle(minutes: Int, fallback: String) -> String {
        switch minutes {
        case 300: return "5-hour limit"
        case 10_080: return "Weekly limit"
        default:
            if minutes.isMultiple(of: 1_440) { return "\(minutes / 1_440)-day limit" }
            if minutes.isMultiple(of: 60) { return "\(minutes / 60)-hour limit" }
            return fallback == "primary" ? "Primary limit" : "Secondary limit"
        }
    }
}

final class CodexUsageClient {
    func fetch(completion: @escaping (Result<CodexSnapshot, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result = self.fetchBlocking()
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func fetchBlocking() -> Result<CodexSnapshot, Error> {
        guard let codexPath = Self.findCodexBinary() else { return .failure(CodexClientError.codexNotFound) }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let collector = CodexResponseCollector(today: Self.localDateString())
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { collector.ingest($0.availableData) }

        do {
            try process.run()
            let messages: [[String: Any]] = [
                ["method": "initialize", "id": 1, "params": ["clientInfo": ["name": "rangeanxiety_menu_bar", "title": "RangeAnxiety", "version": "0.6.0"]]],
                ["method": "initialized", "params": [:]],
                ["method": "account/rateLimits/read", "id": 2],
                ["method": "account/usage/read", "id": 3]
            ]
            for message in messages {
                var data = try JSONSerialization.data(withJSONObject: message)
                data.append(0x0A)
                inputPipe.fileHandleForWriting.write(data)
            }
            if collector.semaphore.wait(timeout: .now() + 15) == .timedOut { collector.completeOnTimeout() }
        } catch {
            collector.completeIfNeeded(.failure(CodexClientError.launchFailed(error.localizedDescription)))
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        try? inputPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        return collector.result ?? .failure(CodexClientError.invalidResponse)
    }

    private static func localDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func findCodexBinary() -> String? {
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
