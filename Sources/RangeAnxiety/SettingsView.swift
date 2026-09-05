import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: UsageModel
    @ObservedObject var updater: UpdaterController
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @StateObject private var cliHealth = CLIHealthController()
    @StateObject private var managedAccounts = ManagedAccountsController()
    @StateObject private var claudeCapture = ClaudeUsageCaptureController()
    @State private var editingProvider: ProviderID?
    @State private var credential = ""
    @State private var auxiliary = ""
    @State private var newAccountName = ""
    @State private var newAccountProvider: ManagedCLIProvider = .codex
    @State private var accountPendingRemoval: ManagedAccount?

    var body: some View {
        TabView {
            providersTab.tabItem { Label("Providers", systemImage: "point.3.connected.trianglepath.dotted") }
            accountsTab.tabItem { Label("Accounts", systemImage: "person.2") }
            toolsTab.tabItem { Label("CLI Health", systemImage: "stethoscope") }
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding(18)
        .frame(width: 680, height: 680)
        .alert("Remove managed account?", isPresented: Binding(
            get: { accountPendingRemoval != nil },
            set: { if !$0 { accountPendingRemoval = nil } }
        ), presenting: accountPendingRemoval) { account in
            Button("Cancel", role: .cancel) { accountPendingRemoval = nil }
            Button("Remove Profile", role: .destructive) {
                managedAccounts.remove(account)
                accountPendingRemoval = nil
            }
        } message: { account in
            Text("This removes only RangeAnxiety’s isolated ‘\(account.nickname)’ profile. Your normal ~/.codex or ~/.claude setup is never touched.")
        }
    }

    private var accountsTab: some View {
        VStack(alignment: .leading, spacing: 13) {
            settingsHeading("Managed CLI accounts", detail: "Each account has an isolated local profile. Activation affects only new sessions launched through the ra command.")
            GroupBox("Add account") {
                HStack {
                    Picker("Provider", selection: $newAccountProvider) {
                        ForEach(ManagedCLIProvider.allCases) { Text($0.displayName).tag($0) }
                    }
                    .frame(width: 170)
                    TextField("Name, for example Work", text: $newAccountName)
                    Button("Add and sign in") {
                        managedAccounts.add(provider: newAccountProvider, nickname: newAccountName)
                        if newAccountProvider == .codex { newAccountName = "" }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newAccountProvider == .claude)
                }
                .padding(4)
                if newAccountProvider == .claude {
                    Text("Claude Code stores subscription credentials in the shared macOS Keychain even when CLAUDE_CONFIG_DIR changes. Managed Claude sign-in stays disabled until RangeAnxiety can verify true account isolation.")
                        .font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let error = managedAccounts.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    if managedAccounts.accounts.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
                            Text("No managed accounts").font(.headline)
                            Text("Your existing default CLI account remains available and unchanged.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 260)
                    }
                    ForEach(managedAccounts.accounts) { account in managedAccountCard(account) }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Text("Launcher: ra codex · ra claude · ra list")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { managedAccounts.refreshAll() }
            }
        }
    }

    private func managedAccountCard(_ account: ManagedAccount) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: account.provider == .codex ? "terminal" : "sparkles")
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(account.nickname).font(.headline)
                        if account.isActive { Text("ACTIVE").font(.system(size: 9, weight: .bold)).foregroundStyle(.green) }
                    }
                    Text("\(account.provider.displayName) · \((managedAccounts.authStates[account.id] ?? .unknown).label)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !account.isActive { Button("Activate") { managedAccounts.activate(account) } }
                Button("Sign in") { managedAccounts.signIn(account) }
                    .disabled(account.provider != .codex)
                Button("Remove", role: .destructive) { accountPendingRemoval = account }
            }
            if let quotaWindows = managedAccounts.windows[account.id], !quotaWindows.isEmpty {
                ForEach(quotaWindows) { window in
                    HStack {
                        Text(window.title).font(.caption)
                        Spacer()
                        Text("\(Int(window.remainingPercent.rounded()))% left").font(.caption.monospacedDigit())
                        if let reset = window.resetsAt { Text("· resets \(reset.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 11))
    }

    private var toolsTab: some View {
        VStack(alignment: .leading, spacing: 13) {
            settingsHeading("CLI health", detail: "Installed versions, authentication state, source, and safe update guidance. RangeAnxiety never runs an update without your action.")
            ForEach(ManagedCLIProvider.allCases) { provider in cliHealthCard(cliHealth.health(for: provider)) }
            Spacer()
            HStack {
                Text(cliHealth.lastUpdated.map { "Checked \($0.formatted(.relative(presentation: .named)))" } ?? "Not checked")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Check again") { cliHealth.refresh() }.disabled(cliHealth.isRefreshing)
            }
        }
    }

    private func cliHealthCard(_ health: CLIToolHealth) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(health.id.displayName, systemImage: health.id == .codex ? "terminal" : "sparkles")
                        .font(.headline)
                    Spacer()
                    Text(cliStateLabel(health.state)).font(.caption.weight(.semibold)).foregroundStyle(cliStateColor(health.state))
                }
                if let version = health.installedVersion { Text(version).font(.system(.caption, design: .monospaced)) }
                if let latest = health.latestVersion { Text("Latest public release: \(latest)").font(.caption2).foregroundStyle(.secondary) }
                if let source = health.installationSource { Text(source).font(.caption).foregroundStyle(.secondary) }
                if let auth = health.authSummary { Text(auth).font(.caption) }
                if let guidance = health.updateGuidance { Text(guidance).font(.caption2).foregroundStyle(.secondary) }
            }
            .padding(4)
        }
    }

    private func cliStateLabel(_ state: CLIHealthState) -> String {
        switch state {
        case .checking: return "CHECKING"
        case .healthy: return "HEALTHY"
        case .needsAttention: return "NEEDS ATTENTION"
        case .notInstalled: return "NOT INSTALLED"
        }
    }

    private func cliStateColor(_ state: CLIHealthState) -> Color {
        switch state {
        case .healthy: return .green
        case .needsAttention: return .orange
        case .checking: return .blue
        case .notInstalled: return .secondary
        }
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
                Toggle("Show Codex and Claude quota bars in the usage menu", isOn: $model.showCodexQuota)
                Toggle("Launch RangeAnxiety at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
            }
            .formStyle(.grouped)
            if let message = launchAtLogin.statusMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            GroupBox("Updates") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic update checks").font(.subheadline.weight(.medium))
                        Text("Updates are verified by Sparkle and the app’s Apple signature.").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
                .padding(4)
            }
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
            } else if descriptor.id == .claudeCode {
                claudeCaptureActions
            } else if case .supported = descriptor.availability, descriptor.requiresCredential {
                connectionActions(descriptor)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 11))
    }

    private var claudeCaptureActions: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Capture limits from Claude Code")
                        .font(.caption.weight(.medium))
                    Text("Opt in once, then send a Claude message. Existing custom status-line output is preserved.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Capture Claude limits", isOn: Binding(
                    get: { claudeCapture.isEnabled },
                    set: { enabled in
                        claudeCapture.setEnabled(enabled)
                        model.refresh()
                    }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            if let message = claudeCapture.statusMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.orange)
            } else if claudeCapture.isEnabled {
                Text("RangeAnxiety stores only the 5-hour and 7-day percentages, reset times, and capture time in Application Support.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 35)
    }

    private func statusBadge(_ descriptor: ProviderDescriptor) -> some View {
        let title: String
        let color: Color
        switch descriptor.availability {
        case .unavailable:
            title = "Not available"; color = .secondary
        case .supported:
            if descriptor.id == .claudeCode {
                title = claudeCapture.isEnabled ? "Capture on" : "Capture off"
                color = claudeCapture.isEnabled ? .green : .secondary
            } else if model.isConfigured(descriptor.id) { title = "Connected"; color = .green }
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
