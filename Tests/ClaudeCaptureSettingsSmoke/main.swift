import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ClaudeCaptureSettingsSmoke {
    @MainActor
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("rangeanxiety-claude-settings-\(UUID().uuidString)")
        let claude = root.appendingPathComponent("claude")
        let support = root.appendingPathComponent("support")
        let launcher = root.appendingPathComponent("ra")
        defer { try? manager.removeItem(at: root) }

        try manager.createDirectory(at: claude, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: launcher)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launcher.path)
        let originalStatusLine: [String: Any] = [
            "type": "command",
            "command": "printf existing",
            "padding": 3,
            "hideVimModeIndicator": true
        ]
        let settings: [String: Any] = ["theme": "dark", "statusLine": originalStatusLine]
        try JSONSerialization.data(withJSONObject: settings).write(to: claude.appendingPathComponent("settings.json"))

        let controller = ClaudeUsageCaptureController(
            manager: manager,
            claudeDirectory: claude,
            supportDirectory: support,
            launcherURL: launcher
        )
        controller.setEnabled(true)
        expect(controller.isEnabled, "capture should be enabled")
        let installedData = try Data(contentsOf: claude.appendingPathComponent("settings.json"))
        let installed = try JSONSerialization.jsonObject(with: installedData) as! [String: Any]
        let installedStatusLine = installed["statusLine"] as! [String: Any]
        expect((installedStatusLine["command"] as? String)?.contains("claude-statusline --out") == true, "wrapper command should be installed")
        expect(installedStatusLine["padding"] as? Int == 3, "existing status-line fields should be retained")

        controller.setEnabled(false)
        expect(!controller.isEnabled, "capture should be disabled")
        let restoredData = try Data(contentsOf: claude.appendingPathComponent("settings.json"))
        let restored = try JSONSerialization.jsonObject(with: restoredData) as! [String: Any]
        let restoredStatusLine = restored["statusLine"] as! [String: Any]
        expect(restoredStatusLine["command"] as? String == "printf existing", "existing command should be restored")
        expect(restored["theme"] as? String == "dark", "unrelated Claude settings should be preserved")
        print("Claude capture settings round-trip smoke checks passed")
    }
}
