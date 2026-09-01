import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: UsageModel
    @State private var editingProvider: ProviderID?
    @State private var credential = ""
    @State private var auxiliary = ""

    var body: some View {
        TabView {
            providersTab.tabItem { Label("Providers", systemImage: "point.3.connected.trianglepath.dotted") }
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding(18)
        .frame(width: 640, height: 650)
    }

    private var providersTab: some View {
        VStack(alignment: .leading, spacing: 13) {
            settingsHeading("Providers", detail: "Connect reporting APIs here. Only connected providers appear in the menu card.")
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(ProviderCatalog.providers) { descriptor in providerCard(descriptor) }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsHeading("General", detail: "Choose what appears in the menu bar and how often connected providers refresh.")
            Form {
                Picker("Menu bar display", selection: $model.menuBarMetric) {
                    ForEach(MenuBarMetric.allCases) { metric in Text(metric.title).tag(metric) }
                }
                Picker("Refresh usage", selection: $model.refreshIntervalMinutes) {
                    Text("Every minute").tag(1)
                    Text("Every 5 minutes").tag(5)
                    Text("Every 15 minutes").tag(15)
                    Text("Every 30 minutes").tag(30)
                }
                Toggle("Show Codex quota bars in the usage menu", isOn: $model.showCodexQuota)
            }
            .formStyle(.grouped)
            GroupBox {
                HStack(spacing: 14) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Support RangeAnxiety").font(.headline)
                        Text("If the app is useful, you can help support its development.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link(destination: URL(string: "https://buymeacoffee.com/kallotech")!) {
                        Text("Buy me a coffee")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(4)
            }
            Spacer()
        }
    }

    private func providerCard(_ descriptor: ProviderDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: descriptor.systemImage)
                    .frame(width: 24).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(descriptor.name).font(.headline)
                        statusBadge(descriptor)
                    }
                    Text(descriptor.detail)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message = unavailableMessage(descriptor) {
                        Text(message).font(.caption2).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if model.isConfigured(descriptor.id), model.canContributeToDailyTotal(descriptor.id) {
                    Toggle("Include in today's total", isOn: Binding(
                        get: { model.isIncluded(descriptor.id) },
                        set: { model.setIncluded(descriptor.id, included: $0) }
                    ))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .help("Include daily values from this provider in the combined total")
                }
            }

            if editingProvider == descriptor.id {
                connectionEditor(descriptor)
            } else if case .supported = descriptor.availability, descriptor.requiresCredential {
                connectionActions(descriptor)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 11))
    }

    private func statusBadge(_ descriptor: ProviderDescriptor) -> some View {
        let title: String
        let color: Color
        switch descriptor.availability {
        case .unavailable:
            title = "Not available"; color = .secondary
        case .supported:
            if model.isConfigured(descriptor.id) { title = "Connected"; color = .green }
            else { title = "Not connected"; color = .secondary }
        }
        return Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func unavailableMessage(_ descriptor: ProviderDescriptor) -> String? {
        switch descriptor.availability {
        case .supported:
            if case .unavailable(let message) = model.usage(for: descriptor.id).state { return message }
            return nil
        case .unavailable(let message): return message
        }
    }

    private func connectionActions(_ descriptor: ProviderDescriptor) -> some View {
        HStack {
            Text(model.needsCredentialAuthorization(descriptor.id)
                 ? "The saved credential needs one-time Keychain authorization."
                 : model.isConfigured(descriptor.id)
                 ? "Credential saved in macOS Keychain. \(UsageFormatting.providerStatus(model.usage(for: descriptor.id)))"
                 : connectionHint(descriptor.id))
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            if model.needsCredentialAuthorization(descriptor.id) {
                Button("Authorize Keychain") { model.authorizeCredential(descriptor.id) }
                    .buttonStyle(.borderedProminent)
                Button("Disconnect") { model.removeCredential(descriptor.id) }
            } else if model.isConfigured(descriptor.id) {
                Button("Replace") { beginEditing(descriptor.id) }
                Button("Disconnect") { model.removeCredential(descriptor.id) }
            } else {
                Button("Connect") { beginEditing(descriptor.id) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func connectionEditor(_ descriptor: ProviderDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField(descriptor.credentialLabel ?? "Credential", text: $credential)
                .textFieldStyle(.roundedBorder)
            if let auxiliaryLabel = descriptor.auxiliaryLabel {
                TextField(auxiliaryLabel, text: $auxiliary).textFieldStyle(.roundedBorder)
            }
            HStack {
                if let title = descriptor.helpTitle, let url = descriptor.helpURL {
                    Link(title, destination: url).font(.caption)
                }
                Spacer()
                Button("Cancel") { cancelEditing() }
                Button("Save connection") {
                    if model.saveCredential(provider: descriptor.id, key: credential, auxiliary: auxiliary) {
                        cancelEditing()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if model.credentialErrorProvider == descriptor.id, let message = model.credentialErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.leading, 35)
    }

    private func connectionHint(_ provider: ProviderID) -> String {
        switch provider {
        case .openRouter: return "Use a management key; it cannot make model requests."
        case .openAI, .anthropic, .mistral: return "An organization admin key is required for usage reporting."
        case .groq: return "Requires GroqCloud Enterprise metrics access."
        default: return "Connect the provider's usage-reporting credential."
        }
    }

    private func beginEditing(_ provider: ProviderID) {
        credential = ""
        auxiliary = ""
        editingProvider = provider
    }
    private func cancelEditing() {
        credential = ""
        auxiliary = ""
        editingProvider = nil
    }
    private func settingsHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.weight(.semibold))
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
