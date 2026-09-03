import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.medium")
            if !model.menuBarText.isEmpty { Text(model.menuBarText) }
        }
        .accessibilityLabel("Usage monitor \(model.menuBarText)")
        .onAppear { model.start() }
    }
}

struct UsagePopover: View {
    @ObservedObject var model: UsageModel
    let settingsPresenter: SettingsWindowPresenter
    @State private var draggedProvider: ProviderID?
    @State private var providerFrames: [ProviderID: CGRect] = [:]

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    combinedUsage
                    ForEach(model.visibleProviderIDs) { provider in
                        providerCard(provider)
                            .background(GeometryReader { proxy in
                                Color.clear.preference(
                                    key: ProviderCardFramesKey.self,
                                    value: [provider: proxy.frame(in: .named("providerCards"))]
                                )
                            })
                            .opacity(draggedProvider == provider ? 0.72 : 1)
                    }

                    if model.visibleProviderIDs.count > 1 {
                        Label("Drag a card by its three-line handle to rearrange", systemImage: "hand.draw")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(15)
            }
            .coordinateSpace(name: "providerCards")
            .onPreferenceChange(ProviderCardFramesKey.self) { providerFrames = $0 }
            .animation(.easeInOut(duration: 0.14), value: model.providerOrder)
            .frame(height: popoverContentHeight)

            Divider()
            footer.padding(.horizontal, 15).padding(.vertical, 10)
        }
        .frame(width: 390)
    }

    private var popoverContentHeight: CGFloat {
        var height: CGFloat = 190
        for provider in model.visibleProviderIDs {
            height += 105
            if provider == .codex, model.showCodexQuota {
                height += CGFloat(model.windows.count) * 62
            }
        }
        if model.visibleProviderIDs.count > 1 { height += 28 }
        return min(570, max(320, height))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Provider usage").font(.headline)
                Text("Connected providers, each in its reported period")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRefreshing { ProgressView().controlSize(.small) }
        }
    }

    private var combinedUsage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TODAY · COMBINED")
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                metric(model.reportedTokensToday.map(UsageFormatting.tokens) ?? "—", label: "tokens")
                Spacer()
                metric(model.reportedSpendToday.map(UsageFormatting.usd) ?? "—", label: "spend", trailing: true)
            }
            Text(coverageText)
                .font(.caption2)
                .foregroundStyle(model.reportingDailyProviderCount == model.includedDailyProviderCount ? Color.secondary : Color.orange)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func metric(_ value: String, label: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var coverageText: String {
        if model.includedDailyProviderCount == 0 { return "No daily providers included in this total" }
        let partial = model.combinedIsPartial ? " · partial response" : ""
        return "\(model.reportingDailyProviderCount) of \(model.includedDailyProviderCount) daily providers reporting\(partial)"
    }

    private func providerCard(_ provider: ProviderID) -> some View {
        let usage = model.usage(for: provider)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: provider.systemImage)
                    .frame(width: 20).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName).font(.subheadline.weight(.semibold))
                    Text(usage.period.label).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(providerColor(usage.state)).frame(width: 7, height: 7)
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.medium))
                    .foregroundStyle(draggedProvider == provider ? Color.accentColor : Color.secondary)
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
                    .gesture(reorderGesture(for: provider))
                    .help("Click and drag to rearrange")
            }

            if provider != .codex {
                providerMetrics(usage)
            }

            if provider == .codex, model.showCodexQuota, !model.windows.isEmpty {
                Divider()
                ForEach(model.windows) { quotaWindow($0) }
            }

            if case .unavailable(let message) = usage.state {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if usage.isPartial {
                Text("The provider marked this response as partial.")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.65), lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func providerMetrics(_ usage: ProviderUsage) -> some View {
        switch usage.state {
        case .loading:
            Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
        case .waiting:
            Text("Waiting for first refresh").font(.caption).foregroundStyle(.secondary)
        case .unconfigured:
            Text("Not connected").font(.caption).foregroundStyle(.secondary)
        case .unavailable:
            EmptyView()
        case .available:
            HStack(alignment: .firstTextBaseline) {
                if let tokens = usage.tokens { metric(UsageFormatting.tokens(tokens), label: tokenLabel(for: usage)) }
                if usage.tokens != nil && usage.spendUSD != nil { Spacer() }
                if let spend = usage.spendUSD { metric(UsageFormatting.usd(spend), label: "spend", trailing: usage.tokens != nil) }
                if usage.tokens == nil && usage.spendUSD == nil {
                    Text("No reported activity").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let secondary = usage.secondaryMetric {
                Text(secondary).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func tokenLabel(for usage: ProviderUsage) -> String {
        usage.period == .recentRate ? "tokens / 5 min" : "tokens"
    }

    private func quotaWindow(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.title).font(.caption.weight(.medium))
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))% left").font(.caption.monospacedDigit())
            }
            AnimatedQuotaBar(
                remainingPercent: window.remainingPercent,
                activity: model.quotaActivity(for: window.id),
                tint: progressColor(for: window.remainingPercent)
            )
            Text(resetDescription(for: window.resetsAt)).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text(model.lastUpdated.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Not updated yet")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).disabled(model.isRefreshing).help("Refresh now")
            if #available(macOS 14.0, *) {
                OpenSettingsButton(presenter: settingsPresenter)
            } else {
                Button {
                    settingsPresenter.show {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                } label: {
                    Image(systemName: "gearshape")
                }.buttonStyle(.borderless).help("Settings").accessibilityLabel("Settings")
            }
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.borderless).help("Quit")
        }
    }

    private func providerColor(_ state: ProviderState) -> Color {
        switch state {
        case .available: return .green
        case .loading: return .blue
        case .unavailable: return .orange
        case .unconfigured, .waiting: return .secondary
        }
    }
    private func resetDescription(for date: Date?) -> String {
        guard let date else { return "Reset time unavailable" }
        return "Resets \(relativeFormatter.localizedString(for: date, relativeTo: Date()))"
    }
    private func progressColor(for remaining: Double) -> Color {
        switch remaining { case ..<10: return .red; case ..<25: return .orange; default: return .accentColor }
    }

    private func reorderGesture(for provider: ProviderID) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("providerCards"))
            .onChanged { value in
                if draggedProvider == nil { draggedProvider = provider }
                guard draggedProvider == provider else { return }
                guard let target = model.visibleProviderIDs.first(where: { candidate in
                    guard let frame = providerFrames[candidate] else { return false }
                    return frame.minY...frame.maxY ~= value.location.y
                }), target != provider else { return }
                model.moveProvider(provider, before: target)
            }
            .onEnded { _ in draggedProvider = nil }
    }
}

private struct ProviderCardFramesKey: PreferenceKey {
    static var defaultValue: [ProviderID: CGRect] = [:]

    static func reduce(value: inout [ProviderID: CGRect], nextValue: () -> [ProviderID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct AnimatedQuotaBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let remainingPercent: Double
    let activity: QuotaActivity
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || activity == .calm)) { timeline in
            GeometryReader { geometry in
                let fillWidth = max(0, geometry.size.width * min(100, remainingPercent) / 100)
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                let shakeX = activity == .rapid && !reduceMotion ? sin(seconds * 27) * 0.55 : 0
                let shakeY = activity == .rapid && !reduceMotion ? cos(seconds * 31) * 0.18 : 0
                let streakWidth = min(geometry.size.width, fillWidth + 18)

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.16))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(fillGradient)
                            .frame(width: fillWidth)
                        if activity != .calm, !reduceMotion, fillWidth > 12 {
                            speedStreaks(width: streakWidth, seconds: seconds)
                                .frame(width: streakWidth, height: 11, alignment: .leading)
                                .clipped()
                        }
                    }
                    .offset(x: shakeX, y: shakeY)
                }
            }
        }
        .frame(height: 7)
        .help(activity.helpText)
        .accessibilityLabel("\(Int(remainingPercent.rounded())) percent quota remaining")
    }

    private var fillGradient: LinearGradient {
        let warmColor: Color
        let transitionPoint: CGFloat
        switch activity {
        case .calm:
            warmColor = tint
            transitionPoint = 1
        case .active:
            warmColor = Color(red: 0.48, green: 0.35, blue: 0.72)
            transitionPoint = 0.82
        case .rapid:
            warmColor = Color(red: 0.78, green: 0.30, blue: 0.38)
            transitionPoint = 0.68
        }
        return LinearGradient(
            stops: [
                .init(color: tint, location: 0),
                .init(color: tint, location: transitionPoint),
                .init(color: warmColor, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func speedStreaks(width: CGFloat, seconds: TimeInterval) -> some View {
        let speed: CGFloat = activity == .rapid ? 42 : 22
        let spacing: CGFloat = activity == .rapid ? 25 : 34
        let travel = max(width + spacing, 1)
        let opacity = activity == .rapid ? 0.40 : 0.26
        return ZStack(alignment: .leading) {
            ForEach(0..<7, id: \.self) { index in
                let position = (CGFloat(seconds) * speed + CGFloat(index) * spacing)
                    .truncatingRemainder(dividingBy: travel) - 11
                Capsule()
                    .fill(Color.white.opacity(opacity))
                    .frame(width: activity == .rapid ? 10 : 7, height: 1.2)
                    .offset(x: position, y: index.isMultiple(of: 2) ? -1.5 : 1.5)
            }
        }
    }
}

enum UsageFormatting {
    static func tokens(_ tokens: Int64) -> String {
        tokens.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(value < 1 ? 3 : 2)))
    }
    static func providerStatus(_ usage: ProviderUsage) -> String {
        switch usage.state {
        case .waiting: return "Waiting"
        case .loading: return "Refreshing…"
        case .unconfigured: return "Not connected"
        case .unavailable: return "Unavailable"
        case .available:
            var parts: [String] = []
            if let tokens = usage.tokens { parts.append("\(self.tokens(tokens)) tok") }
            if let spend = usage.spendUSD { parts.append(usd(spend)) }
            if usage.isPartial { parts.append("partial") }
            return parts.isEmpty ? "Connected" : parts.joined(separator: " · ")
        }
    }
}
