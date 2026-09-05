import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL \(message)\n", stderr)
        exit(1)
    }
}

let response: [String: Any] = [
    "result": [
        "rateLimitsByLimitId": [
            "codex": [
                "limitId": "codex",
                "primary": ["usedPercent": 25, "windowDurationMins": 300, "resetsAt": 1_730_947_200],
                "secondary": ["usedPercent": 60, "windowDurationMins": 10_080, "resetsAt": 1_731_000_000]
            ],
            "codex_other": [
                "limitId": "codex_other",
                "limitName": "Other model",
                "primary": ["usedPercent": 42, "windowDurationMins": 60, "resetsAt": 1_730_950_800]
            ]
        ]
    ]
]

let windows = CodexManagedAccountReader.parseWindows(response)
expect(windows.count == 3, "all multi-bucket windows should be preserved")
expect(windows.contains(where: { $0.id == "codex-primary" && $0.remainingPercent == 75 }), "primary window should parse")
expect(windows.contains(where: { $0.title == "Other model" && $0.remainingPercent == 58 }), "model-scoped window should keep its label")
print("Managed account parser smoke checks passed")
