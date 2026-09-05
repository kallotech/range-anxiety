import Foundation
import SwiftUI

@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var quotaWindowsByProvider: [ProviderID: [QuotaWindow]] = [:]
    @Published private(set) var quotaBurnRates: [String: Double] = [:]
    @Published private(set) var usages: [ProviderID: ProviderUsage] = [:]
    @Published private(set) var connectedProviderIDs: Set<ProviderID> = [.codex]
    @Published private(set) var providerOrder: [ProviderID]
    @Published private(set) var includedProviderIDs: Set<ProviderID>
    @Published private(set) var isRefreshing = false
    @Published private(set) var quotaErrorMessage: String?
    @Published private(set) var credentialErrorMessage: String?
    @Published private(set) var credentialErrorProvider: ProviderID?
    @Published private(set) var credentialAuthorizationNeeded: Set<ProviderID> = []
    @Published private(set) var lastUpdated: Date?

    @Published var refreshIntervalMinutes: Int {
        didSet {
            defaults.set(refreshIntervalMinutes, forKey: Self.refreshIntervalKey)
            if started { scheduleTimer() }
        }
    }
    @Published var menuBarMetric: MenuBarMetric {
        didSet { defaults.set(menuBarMetric.rawValue, forKey: Self.menuBarMetricKey) }
    }
    @Published var showCodexQuota: Bool {
        didSet { defaults.set(showCodexQuota, forKey: Self.showQuotaKey) }
    }

    private static let includedProvidersKey = "includedProviderIDs.v2"
    private static let providerOrderKey = "providerOrder.v2"
    private static let refreshIntervalKey = "refreshIntervalMinutes"
    private static let menuBarMetricKey = "menuBarMetric"
    private static let showQuotaKey = "showCodexQuota"
    private static let legacyDefaultsDomain = "com.local.codexquota"
    private static let defaultsMigrationKey = "migratedDefaultsFromCodexQuota.v1"
    private let defaults: UserDefaults
    private let adapters: [ProviderID: any UsageProviderAdapter]
    private var started = false
    private var refreshTimer: Timer?
    private var refreshID = UUID()
    private var pendingResponses = 0
    private var lastQuotaSampleDates: [ProviderID: Date] = [:]
    private var lastQuotaUsedPercent: [ProviderID: [String: Double]] = [:]

    init(defaults: UserDefaults = .standard) {
        Self.migrateLegacyDefaultsIfNeeded(into: defaults)
        self.defaults = defaults
        self.adapters = ProviderAdapterFactory.makeAdapters()

        let savedOrder = defaults.stringArray(forKey: Self.providerOrderKey)?.compactMap(ProviderID.init(rawValue:)) ?? []
        providerOrder = savedOrder + ProviderID.allCases.filter { !savedOrder.contains($0) }

        if let savedIncluded = defaults.stringArray(forKey: Self.includedProvidersKey) {
            includedProviderIDs = Set(savedIncluded.compactMap(ProviderID.init(rawValue:)))
        } else {
            let includeCodex = defaults.object(forKey: "includeCodexInTotals") as? Bool ?? true
            let includeOpenRouter = defaults.object(forKey: "includeOpenRouterInTotals") as? Bool ?? true
            includedProviderIDs = Set([includeCodex ? .codex : nil, includeOpenRouter ? .openRouter : nil].compactMap { $0 })
        }

        let savedInterval = defaults.object(forKey: Self.refreshIntervalKey) as? Int ?? 5
        refreshIntervalMinutes = [1, 5, 15, 30].contains(savedInterval) ? savedInterval : 5
        menuBarMetric = MenuBarMetric(rawValue: defaults.string(forKey: Self.menuBarMetricKey) ?? "") ?? .quotaRemaining
        showCodexQuota = defaults.object(forKey: Self.showQuotaKey) as? Bool ?? true
        usages = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, ProviderUsage.waiting($0)) })
        reloadConnectionStatus()
    }

    private static func migrateLegacyDefaultsIfNeeded(into defaults: UserDefaults) {
        guard Bundle.main.bundleIdentifier == "io.github.kallotech.rangeanxiety",
              defaults.object(forKey: defaultsMigrationKey) == nil else { return }

        if let legacyValues = defaults.persistentDomain(forName: legacyDefaultsDomain) {
            for (key, value) in legacyValues where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: defaultsMigrationKey)
    }

    var menuBarText: String {
        switch menuBarMetric {
        case .quotaRemaining:
            guard let primary = windows(for: .codex).first else { return isRefreshing ? "…" : "!" }
            return "\(Int(primary.remainingPercent.rounded()))%"
        case .tokensToday:
            guard let tokens = reportedTokensToday else { return isRefreshing ? "…" : "—" }
            return tokens.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
        case .iconOnly: return ""
        }
    }

    var visibleProviderIDs: [ProviderID] { providerOrder.filter(connectedProviderIDs.contains) }
    var reportedTokensToday: Int64? { sumDaily(\.tokens) }
    var reportedSpendToday: Double? { sumDaily(\.spendUSD) }
    var combinedIsPartial: Bool { includedDailyUsages.contains(where: \.isPartial) }
    var includedDailyProviderCount: Int {
        connectedProviderIDs.intersection(includedProviderIDs).filter(Self.hasDailyReporting).count
    }
    var reportingDailyProviderCount: Int {
        includedDailyUsages.filter { $0.tokens != nil || $0.spendUSD != nil }.count
    }

    private var includedDailyUsages: [ProviderUsage] {
        connectedProviderIDs.intersection(includedProviderIDs)
            .compactMap { usages[$0] }
            .filter { $0.period.contributesToDailyTotal }
    }

    private static func hasDailyReporting(_ id: ProviderID) -> Bool {
        [.openRouter, .openAI, .anthropic].contains(id)
    }

    private func sumDaily<T: AdditiveArithmetic>(_ keyPath: KeyPath<ProviderUsage, T?>) -> T? {
        let values = includedDailyUsages.compactMap { $0[keyPath: keyPath] }
        return values.isEmpty ? nil : values.reduce(.zero, +)
    }

    func usage(for provider: ProviderID) -> ProviderUsage { usages[provider] ?? .waiting(provider) }
    func windows(for provider: ProviderID) -> [QuotaWindow] { quotaWindowsByProvider[provider] ?? [] }
    func quotaActivity(for windowID: String) -> QuotaActivity {
        QuotaActivity(pointsPerMinute: quotaBurnRates[windowID] ?? 0)
    }
    func isConfigured(_ provider: ProviderID) -> Bool { connectedProviderIDs.contains(provider) }
    func needsCredentialAuthorization(_ provider: ProviderID) -> Bool { credentialAuthorizationNeeded.contains(provider) }
    func isIncluded(_ provider: ProviderID) -> Bool { includedProviderIDs.contains(provider) }
    func canContributeToDailyTotal(_ provider: ProviderID) -> Bool { Self.hasDailyReporting(provider) }

    func setIncluded(_ provider: ProviderID, included: Bool) {
        if included { includedProviderIDs.insert(provider) } else { includedProviderIDs.remove(provider) }
        persistIncludedProviders()
    }

    func start() {
        guard !started else { return }
        started = true
        refresh()
        scheduleTimer()
    }

    func refresh() {
        guard !isRefreshing else { return }
        let providers = visibleProviderIDs.compactMap { adapters[$0] }
        refreshID = UUID()
        let currentID = refreshID
        isRefreshing = true
        quotaErrorMessage = nil
        pendingResponses = providers.count
        for adapter in providers {
            updateUsage(adapter.id) { $0.state = .loading }
            adapter.fetch { [weak self] result in
                guard let self, self.refreshID == currentID else { return }
                self.apply(result, from: adapter.id)
                self.finishOne(refreshID: currentID)
            }
        }
        if providers.isEmpty { finishRefresh() }
    }

    @discardableResult
    func saveCredential(provider: ProviderID, key rawKey: String, auxiliary rawAuxiliary: String?) -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let auxiliary = rawAuxiliary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor = provider.descriptor
        guard !key.isEmpty else { return credentialFailure(provider, "Enter the \(descriptor.credentialLabel?.lowercased() ?? "credential").") }
        if descriptor.auxiliaryRequired, auxiliary?.isEmpty != false {
            return credentialFailure(provider, "Enter the \(descriptor.auxiliaryLabel ?? "required ID").")
        }
        do {
            try ProviderCredentialStore.save(ProviderCredential(key: key, auxiliary: auxiliary?.isEmpty == false ? auxiliary : nil), for: provider)
            connectedProviderIDs.insert(provider)
            includedProviderIDs.insert(provider)
            persistIncludedProviders()
            credentialErrorMessage = nil
            credentialErrorProvider = nil
            credentialAuthorizationNeeded.remove(provider)
            updateUsage(provider) { $0 = .waiting(provider) }
            refreshAfterConfigurationChange()
            return true
        } catch { return credentialFailure(provider, error.localizedDescription) }
    }

    func removeCredential(_ provider: ProviderID) {
        do {
            try ProviderCredentialStore.remove(provider)
            connectedProviderIDs.remove(provider)
            includedProviderIDs.remove(provider)
            persistIncludedProviders()
            updateUsage(provider) { $0.state = .unconfigured }
            credentialErrorMessage = nil
            credentialErrorProvider = nil
            credentialAuthorizationNeeded.remove(provider)
        } catch { _ = credentialFailure(provider, error.localizedDescription) }
    }

    func authorizeCredential(_ provider: ProviderID) {
        do {
            guard try ProviderCredentialStore.authorize(provider) != nil else {
                _ = credentialFailure(provider, "The saved Keychain item could not be found. Reconnect this provider.")
                return
            }
            connectedProviderIDs.insert(provider)
            credentialAuthorizationNeeded.remove(provider)
            credentialErrorMessage = nil
            credentialErrorProvider = nil
            updateUsage(provider) { $0 = .waiting(provider) }
            refreshAfterConfigurationChange()
        } catch {
            _ = credentialFailure(provider, error.localizedDescription)
        }
    }

    func moveProvider(_ dragged: ProviderID, before target: ProviderID) {
        guard dragged != target, let from = providerOrder.firstIndex(of: dragged),
              let originalTarget = providerOrder.firstIndex(of: target) else { return }
        providerOrder.remove(at: from)
        providerOrder.insert(dragged, at: min(originalTarget, providerOrder.count))
        defaults.set(providerOrder.map(\.rawValue), forKey: Self.providerOrderKey)
    }

    private func apply(_ result: Result<ProviderFetchResult, Error>, from provider: ProviderID) {
        switch result {
        case .success(let value):
            usages[provider] = value.usage
            if provider.isSubscriptionQuotaProvider {
                updateQuotaBurnRates(for: provider, with: value.quotaWindows, sampledAt: Date())
                quotaWindowsByProvider[provider] = value.quotaWindows
            }
        case .failure(let error):
            let isUnconfigured: Bool
            if case ProviderAdapterError.notConfigured = error { isUnconfigured = true } else { isUnconfigured = false }
            updateUsage(provider) { usage in
                usage.tokens = nil
                usage.spendUSD = nil
                usage.state = isUnconfigured ? .unconfigured : .unavailable(error.localizedDescription)
            }
            if provider == .codex { quotaErrorMessage = error.localizedDescription }
        }
    }

    private func reloadConnectionStatus() {
        connectedProviderIDs = [.codex, .claudeCode]
        for descriptor in ProviderCatalog.providers where descriptor.requiresCredential {
            do {
                if try ProviderCredentialStore.read(descriptor.id) != nil { connectedProviderIDs.insert(descriptor.id) }
                else { updateUsage(descriptor.id) { $0.state = .unconfigured } }
            } catch CredentialStoreError.keychainAccessChanged {
                connectedProviderIDs.insert(descriptor.id)
                credentialAuthorizationNeeded.insert(descriptor.id)
                updateUsage(descriptor.id) {
                    $0.state = .unavailable("Authorize this saved credential once in Settings after the signing upgrade.")
                }
            } catch {
                credentialErrorMessage = error.localizedDescription
                credentialErrorProvider = descriptor.id
                updateUsage(descriptor.id) { $0.state = .unavailable(error.localizedDescription) }
            }
        }
    }

    private func credentialFailure(_ provider: ProviderID, _ message: String) -> Bool {
        credentialErrorProvider = provider
        credentialErrorMessage = message
        return false
    }

    private func updateQuotaBurnRates(for provider: ProviderID, with newWindows: [QuotaWindow], sampledAt date: Date) {
        guard let previousDate = lastQuotaSampleDates[provider] else {
            lastQuotaSampleDates[provider] = date
            lastQuotaUsedPercent[provider] = Dictionary(uniqueKeysWithValues: newWindows.map { ($0.id, $0.usedPercent) })
            return
        }
        let elapsedSeconds = date.timeIntervalSince(previousDate)
        guard elapsedSeconds >= 30 else { return }
        let elapsedMinutes = elapsedSeconds / 60
        var newRates: [String: Double] = [:]
        let previousValues = lastQuotaUsedPercent[provider] ?? [:]
        for window in newWindows {
            guard let previous = previousValues[window.id] else { continue }
            newRates[window.id] = max(0, window.usedPercent - previous) / elapsedMinutes
        }
        for (id, rate) in newRates { quotaBurnRates[id] = rate }
        lastQuotaSampleDates[provider] = date
        lastQuotaUsedPercent[provider] = Dictionary(uniqueKeysWithValues: newWindows.map { ($0.id, $0.usedPercent) })
    }

    private func persistIncludedProviders() {
        defaults.set(includedProviderIDs.map(\.rawValue).sorted(), forKey: Self.includedProvidersKey)
    }

    private func updateUsage(_ provider: ProviderID, mutation: (inout ProviderUsage) -> Void) {
        var value = usage(for: provider)
        mutation(&value)
        usages[provider] = value
    }

    private func refreshAfterConfigurationChange() {
        isRefreshing = false
        refresh()
    }

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: TimeInterval(refreshIntervalMinutes * 60), repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func finishOne(refreshID: UUID) {
        guard self.refreshID == refreshID else { return }
        pendingResponses -= 1
        if pendingResponses <= 0 { finishRefresh() }
    }

    private func finishRefresh() {
        isRefreshing = false
        lastUpdated = Date()
    }
}
