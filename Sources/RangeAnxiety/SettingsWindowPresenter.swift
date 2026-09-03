import AppKit
import SwiftUI

/// Keeps SwiftUI's native Settings scene, but explicitly fronts it for this menu-bar-only app.
@MainActor
final class SettingsWindowPresenter: ObservableObject {
    private weak var settingsWindow: NSWindow?
    private var presentationRequested = false

    func show(openSettings: () -> Void) {
        presentationRequested = true
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        bringForwardIfRequested()
    }

    func attach(_ window: NSWindow) {
        settingsWindow = window
        bringForwardIfRequested()
    }

    private func bringForwardIfRequested() {
        guard presentationRequested, let window = settingsWindow else { return }
        presentationRequested = false

        // Move to the desktop where Settings was requested, without floating above other apps.
        window.collectionBehavior.insert(.moveToActiveSpace)
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

/// Captures the actual Settings window, not whichever app window happens to be first.
struct SettingsWindowReader: NSViewRepresentable {
    let presenter: SettingsWindowPresenter

    func makeNSView(context: Context) -> WindowReaderView {
        WindowReaderView(presenter: presenter)
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {}

    final class WindowReaderView: NSView {
        let presenter: SettingsWindowPresenter

        init(presenter: SettingsWindowPresenter) {
            self.presenter = presenter
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Finish SwiftUI's window setup before responding to a first-open request.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                self.presenter.attach(window)
            }
        }
    }
}

@available(macOS 14.0, *)
struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings
    let presenter: SettingsWindowPresenter

    var body: some View {
        Button {
            presenter.show { openSettings() }
        } label: {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.borderless)
        .help("Settings")
        .accessibilityLabel("Settings")
    }
}
