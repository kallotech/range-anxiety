import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
        refresh()
    }
}
