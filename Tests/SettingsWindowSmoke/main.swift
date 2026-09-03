import AppKit

@MainActor
final class RecordingWindow: NSWindow {
    var foregroundRequests = 0
    var orderRequests = 0
    var restoreRequests = 0
    var simulatedMinimized = false

    override var isMiniaturized: Bool { simulatedMinimized }
    override func makeKeyAndOrderFront(_ sender: Any?) { foregroundRequests += 1 }
    override func orderFrontRegardless() { orderRequests += 1 }
    override func deminiaturize(_ sender: Any?) {
        restoreRequests += 1
        simulatedMinimized = false
    }
}

@main
struct SettingsWindowSmoke {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let presenter = SettingsWindowPresenter()
        let window = RecordingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 650),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: true
        )
        var openRequests = 0

        // The first click can precede SwiftUI creating/attaching its Settings window.
        presenter.show { openRequests += 1 }
        precondition(window.foregroundRequests == 0)
        presenter.attach(window)
        precondition(window.foregroundRequests == 1 && window.orderRequests == 1)
        precondition(window.collectionBehavior.contains(.moveToActiveSpace))
        precondition(window.level == .normal)

        // SwiftUI updating its view must not steal focus without another click.
        presenter.attach(window)
        precondition(window.foregroundRequests == 1)

        // An existing/obscured Settings window is raised again on every click.
        presenter.show { openRequests += 1 }
        precondition(window.foregroundRequests == 2 && window.orderRequests == 2)

        window.simulatedMinimized = true
        presenter.show { openRequests += 1 }
        precondition(window.restoreRequests == 1 && !window.isMiniaturized)
        precondition(window.foregroundRequests == 3 && window.level == .normal)
        precondition(openRequests == 3)

        // A window already attached before the very first request is also handled.
        let alreadyAttached = SettingsWindowPresenter()
        alreadyAttached.attach(window)
        precondition(window.foregroundRequests == 3)
        alreadyAttached.show {}
        precondition(window.foregroundRequests == 4)
        print("Settings window smoke checks passed (deferred open, repeat, restore, focus, normal level).")
    }
}
