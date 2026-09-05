import Foundation

enum ClaudeUsageCaptureError: LocalizedError {
    case notConfigured
    case invalidCapture
    case noLimits

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Enable Claude limit capture in Settings, then send a message in Claude Code."
        case .invalidCapture:
            return "Claude's saved limit snapshot could not be read."
        case .noLimits:
            return "Claude has not supplied subscription limits yet. Send a message in a signed-in Pro or Max session."
        }
    }
}

enum ClaudeUsageCapturePaths {
    static var captureURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RangeAnxiety/claude-usage.json")
    }
}

final class ClaudeUsageCaptureClient {
    func fetch(completion: @escaping (Result<[QuotaWindow], Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result: Result<[QuotaWindow], Error>
            do {
                let data = try Data(contentsOf: ClaudeUsageCapturePaths.captureURL)
                result = .success(try Self.parse(data))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                result = .failure(ClaudeUsageCaptureError.notConfigured)
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> [QuotaWindow] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageCaptureError.invalidCapture
        }
        var windows: [QuotaWindow] = []
        if let window = parseWindow(root["five_hour"], id: "claude-five-hour", title: "5-hour limit", duration: 300, now: now) {
            windows.append(window)
        }
        if let window = parseWindow(root["seven_day"], id: "claude-seven-day", title: "7-day limit", duration: 10_080, now: now) {
            windows.append(window)
        }
        guard !windows.isEmpty else { throw ClaudeUsageCaptureError.noLimits }
        return windows
    }

    private static func parseWindow(
        _ value: Any?, id: String, title: String, duration: Int, now: Date
    ) -> QuotaWindow? {
        guard let raw = value as? [String: Any],
              let used = (raw["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
        let resetValue = raw["resets_at"]
        let resetsAt: Date?
        if let seconds = (resetValue as? NSNumber)?.doubleValue {
            resetsAt = Date(timeIntervalSince1970: seconds)
        } else if let text = resetValue as? String {
            resetsAt = ISO8601DateFormatter().date(from: text)
        } else {
            resetsAt = nil
        }
        if let resetsAt, resetsAt <= now { return nil }
        return QuotaWindow(
            id: id,
            title: title,
            usedPercent: min(100, max(0, used)),
            durationMinutes: duration,
            resetsAt: resetsAt
        )
    }
}
