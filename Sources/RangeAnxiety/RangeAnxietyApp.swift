import SwiftUI

@main
struct RangeAnxietyApp: App {
    @StateObject private var model = UsageModel()
    @StateObject private var settingsPresenter = SettingsWindowPresenter()

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(model: model, settingsPresenter: settingsPresenter)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
                .background(SettingsWindowReader(presenter: settingsPresenter))
        }
    }
}
