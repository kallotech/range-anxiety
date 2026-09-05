import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL \(message)\n", stderr)
        exit(1)
    }
}

let capture = Data("""
{
  "observedAt": "2026-09-05T00:00:00Z",
  "five_hour": {"used_percentage": 27.5, "resets_at": 1788577200},
  "seven_day": {"used_percentage": 61, "resets_at": "2026-09-10T00:00:00Z"}
}
""".utf8)

do {
    let now = ISO8601DateFormatter().date(from: "2026-09-05T00:00:00Z")!
    let windows = try ClaudeUsageCaptureClient.parse(capture, now: now)
    expect(windows.count == 2, "both Claude subscription windows should parse")
    expect(windows[0].id == "claude-five-hour", "the 5-hour window should have a provider-scoped id")
    expect(windows[0].remainingPercent == 72.5, "the 5-hour remaining percentage should be calculated")
    expect(windows[1].title == "7-day limit", "the weekly window should be labelled")
    expect(windows[1].resetsAt != nil, "ISO reset timestamps should parse")
    let afterReset = ISO8601DateFormatter().date(from: "2026-09-11T00:00:00Z")!
    do {
        _ = try ClaudeUsageCaptureClient.parse(capture, now: afterReset)
        expect(false, "expired windows should not be displayed")
    } catch ClaudeUsageCaptureError.noLimits {
        // Expected: Claude must provide a fresh snapshot after the reset.
    }
    print("Claude usage capture parser smoke checks passed")
} catch {
    fputs("FAIL unexpected error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
