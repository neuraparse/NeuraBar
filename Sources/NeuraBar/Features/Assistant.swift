import SwiftUI
import AppKit

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var text: String
    var providerID: String?
    var automationRun: AutomationRun?  // populated when this bubble is an automation result
    var startedAt: Date = Date()       // used for "elapsed" rendering on streaming msgs
    enum Role { case user, assistant, system, automation }
}

/// Pending approval request — shown as an inline banner with Approve / Cancel.
struct PendingApproval: Identifiable {
    let id = UUID()
    let automationID: String
    let automationTitle: String
    let reason: String   // "AI suggested" or "You asked"
}

struct AssistantView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var l10n: Localization
    @EnvironmentObject var store: AppStore
    @State private var input: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var sending = false
    @State private var error: String?
    @State private var providers: [AIProvider] = []
    @State private var selected: AIProvider?
    @State private var runningProcess: Process?
    @State private var showProviderPicker = false
    @State private var showSlashMenu = false
    @State private var pending: PendingApproval?
    @State private var elapsedTick = 0  // forces re-render for live elapsed counter

    private let elapsedTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Destructive automations that always require explicit approval before running.
    private static let destructiveAutomations: Set<String> = [
        "trash", "dsstore", "derived", "lock", "sleep"
    ]

    var body: some View {
        VStack(spacing: 8) {
            providerBar

            if providers.isEmpty {
                emptyStateNoProviders
            } else {
                chatArea
                if let p = pending { approvalBanner(for: p) }
                quickActionsBar
                composer
                if showSlashMenu { slashMenu }
            }
        }
        .onAppear(perform: refreshProviders)
        .onChange(of: settings.data.claudeAPIKey) { refreshProviders() }
        .onChange(of: settings.data.openaiAPIKey) { refreshProviders() }
        .onReceive(elapsedTimer) { _ in
            if sending { elapsedTick &+= 1 }
        }
        .onChange(of: input) { _, newValue in
            // Show slash menu when the user starts with "/" and hasn't added a space.
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            showSlashMenu = trimmed.hasPrefix("/") && !trimmed.contains(" ")
        }
    }

    // MARK: - Provider bar

    private var providerBar: some View {
        HStack(spacing: 6) {
            if let sel = selected {
                Button {
                    showProviderPicker.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: sel.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(sel.name)
                            .font(.system(size: 11, weight: .semibold))
                        Text(sel.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(badgeColor(for: sel).opacity(0.16))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(badgeColor(for: sel).opacity(0.35), lineWidth: 0.6)
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showProviderPicker, arrowEdge: .bottom) {
                    providerPicker
                }
            }
            Spacer()
            Text("\(providers.count) \(l10n.t(.ai_providers_count))")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Button {
                refreshProviders()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(l10n.t(.ai_rescan))
        }
    }

    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(l10n.t(.ai_picker_title))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ForEach(providers) { p in
                Button {
                    selected = p
                    settings.data.preferredProviderID = p.id
                    showProviderPicker = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: p.icon)
                            .frame(width: 18)
                            .foregroundStyle(badgeColor(for: p))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(.system(size: 12, weight: .medium))
                            Text(p.subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selected?.id == p.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider()
            Text(detectionHint)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(12)
        }
        .frame(width: 280)
    }

    private var detectionHint: String {
        let cli = providers.filter { $0.kind == .cli }.count
        let api = providers.filter { $0.kind == .api }.count
        let desk = providers.filter { $0.kind == .desktop }.count
        return l10n.t(.ai_picker_hint, cli, api, desk)
    }

    private func badgeColor(for p: AIProvider) -> Color {
        switch p.kind {
        case .cli: return .green
        case .api: return .purple
        case .desktop: return .blue
        }
    }

    // MARK: - Chat area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if messages.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: selected?.icon ?? "sparkles")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                            Text(l10n.t(.ai_emptyPrompt))
                                .font(.callout)
                            if let sel = selected {
                                Text(sel.kind == .desktop
                                     ? l10n.t(.ai_emptyDesktopHint, sel.name)
                                     : l10n.t(.ai_emptyCLIHint, sel.name))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                    ForEach(messages) { m in
                        MessageBubble(message: m).id(m.id)
                    }
                    if sending {
                        sendingIndicator
                            .id(elapsedTick) // force refresh each second
                    }
                    if let err = error {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.08)))
                    }
                }
            }
            .onChange(of: messages.last?.text) {
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 6) {
            TextField(placeholderText, text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06))
                )
                .onSubmit { send() }

            Button { send() } label: {
                Image(systemName: selected?.kind == .desktop ? "arrow.up.forward.app.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(sending || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var placeholderText: String {
        guard let s = selected else { return l10n.t(.ai_emptyPrompt) }
        switch s.kind {
        case .cli: return l10n.t(.ai_placeholder_cli, s.name)
        case .api: return l10n.t(.ai_placeholder_api, s.name)
        case .desktop: return l10n.t(.ai_placeholder_desktop)
        }
    }

    // MARK: - Sending indicator (rich)

    private var sendingIndicator: some View {
        let elapsed = messages.last(where: { $0.role == .assistant })?.startedAt ?? Date()
        let secs = Int(Date().timeIntervalSince(elapsed))
        return HStack(spacing: 7) {
            BrandPulse(size: 14)
            Text(l10n.t(.thinking))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let sel = selected {
                Text("· \(sel.name)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if secs > 0 {
                Text("· \(secs)s")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if runningProcess != nil {
                Button(l10n.t(.stop)) { stopRunning() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    // MARK: - Quick actions bar

    /// Context-aware automation suggestions. Suggestions are picked by matching
    /// keywords in the user's last message, else shows a rotating starter set.
    private var quickActionsBar: some View {
        let suggestions = suggestedAutomations()
        return Group {
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("⚡")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(suggestions, id: \.id) { def in
                            Button {
                                requestAutomation(def, reason: "You tapped")
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: def.icon)
                                        .font(.system(size: 9, weight: .medium))
                                    Text(l10n.t(def.titleKey))
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundStyle(def.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(def.color.opacity(0.14))
                                )
                                .overlay(
                                    Capsule().strokeBorder(def.color.opacity(0.28), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .frame(height: 24)
            }
        }
    }

    private func suggestedAutomations() -> [AutomationDef] {
        let lastUser = messages.last(where: { $0.role == .user })?.text.lowercased() ?? ""
        let keywordMap: [(keywords: [String], ids: [String])] = [
            (["screenshot", "ekran görüntüsü"], ["screenshots", "sortDL"]),
            (["download", "indir"], ["sortDL", "dmg", "oldDL"]),
            (["clean", "temizle", "cleanup", "çöp"], ["dsstore", "dmg", "trash", "derived"]),
            (["trash", "çöp"], ["trash"]),
            (["heic"], ["heic"]),
            (["xcode", "derived"], ["derived"]),
            (["big", "büyük", "large"], ["bigFiles"]),
            (["lock", "kilit"], ["lock"]),
            (["sleep", "uyut"], ["sleep"]),
            (["hidden", "gizli"], ["hidden"])
        ]
        var ids: [String] = []
        for entry in keywordMap {
            if entry.keywords.contains(where: { lastUser.contains($0) }) {
                ids.append(contentsOf: entry.ids)
            }
        }
        if ids.isEmpty {
            // Default starter set
            ids = ["screenshots", "sortDL", "trash", "bigFiles"]
        }
        var seen = Set<String>()
        return ids.compactMap { id in
            guard !seen.contains(id), let def = AutomationCatalog.all.first(where: { $0.id == id }) else { return nil }
            seen.insert(id)
            return def
        }
        .prefix(5).map { $0 }
    }

    // MARK: - Slash menu

    private var slashMenu: some View {
        let q = input.trimmingCharacters(in: .whitespaces).dropFirst().lowercased() // drop leading "/"
        let candidates = AutomationCatalog.all.filter {
            q.isEmpty || $0.id.lowercased().contains(q) || l10n.t($0.titleKey).lowercased().contains(q)
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text("/automate")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(candidates.prefix(6)) { def in
                        Button {
                            input = ""
                            showSlashMenu = false
                            requestAutomation(def, reason: "Slash command")
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: def.icon)
                                    .foregroundStyle(def.color)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(l10n.t(def.titleKey))
                                        .font(.system(size: 11, weight: .medium))
                                    Text("/\(def.id)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .nbHoverHighlight(cornerRadius: 5, intensity: 0.06)
                    }
                }
            }
            .frame(maxHeight: 160)
        }
        .nbCard()
    }

    // MARK: - Approval banner

    private func approvalBanner(for p: PendingApproval) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(p.reason): \(p.automationTitle)")
                    .font(.system(size: 11, weight: .medium))
                Text("Approve to execute. Destructive actions require confirmation.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(l10n.t(.cancel)) { pending = nil }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Button("Approve") {
                guard let def = AutomationCatalog.all.first(where: { $0.id == p.automationID }) else { return }
                pending = nil
                runAutomation(def)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.orange)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: NB.rMd, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NB.rMd, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.7)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Automation runner

    /// Entry point from any trigger (slash cmd, chip, AI response). Decides
    /// whether to ask for approval or run directly.
    func requestAutomation(_ def: AutomationDef, reason: String) {
        if Self.destructiveAutomations.contains(def.id) {
            withAnimation(.spring(duration: 0.28, bounce: 0.2)) {
                pending = PendingApproval(
                    automationID: def.id,
                    automationTitle: l10n.t(def.titleKey),
                    reason: reason
                )
            }
        } else {
            runAutomation(def)
        }
    }

    private func runAutomation(_ def: AutomationDef) {
        // Insert a placeholder "running" bubble we update on completion.
        let placeholder = ChatMessage(
            role: .automation,
            text: l10n.t(def.titleKey),
            providerID: def.id
        )
        messages.append(placeholder)
        let placeholderID = placeholder.id

        Task { @MainActor in
            await store.automation.run(def, l10n: l10n)
            if let run = store.automation.history.first(where: { $0.taskID == def.id }),
               let idx = messages.firstIndex(where: { $0.id == placeholderID }) {
                var updated = messages[idx]
                updated.automationRun = run
                messages[idx] = updated
            }
        }
    }

    // MARK: - Empty state (no providers / no keys)

    private var emptyStateNoProviders: some View {
        VStack(spacing: 14) {
            Image(systemName: "key.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(l10n.t(.ai_providers_emptyTitle))
                .font(.callout.bold())
            Text(l10n.t(.ai_providers_emptyBody))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            VStack(spacing: 6) {
                Link("Claude API key →", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
                Link("OpenAI API key →", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
                Link("Claude Code CLI kur →", destination: URL(string: "https://docs.claude.com/en/docs/claude-code")!)
                    .font(.caption)
            }
            .padding(.top, 4)

            Button {
                refreshProviders()
            } label: {
                Label(l10n.t(.ai_rescan), systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func refreshProviders() {
        let list = AIDetector.detect(settings: settings.data)
        self.providers = list
        if let pref = list.first(where: { $0.id == settings.data.preferredProviderID }) {
            self.selected = pref
        } else {
            self.selected = list.first
            if let first = list.first { settings.data.preferredProviderID = first.id }
        }
    }

    private func stopRunning() {
        runningProcess?.terminate()
        runningProcess = nil
        sending = false
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let provider = selected else { return }
        input = ""
        error = nil
        showSlashMenu = false

        // Slash commands — /auto <id> or just /<id> runs an automation.
        if text.hasPrefix("/") {
            let raw = String(text.dropFirst())
            let token = raw.replacingOccurrences(of: "auto ", with: "")
                .replacingOccurrences(of: "automate ", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let def = AutomationCatalog.all.first(where: { $0.id.lowercased() == token.lowercased() }) {
                messages.append(ChatMessage(role: .user, text: text))
                requestAutomation(def, reason: "You ran")
                return
            }
            // Unknown slash command — fall through to the model
            messages.append(ChatMessage(
                role: .system,
                text: "Unknown command: /\(token). Try /screenshots, /trash, /heic …"
            ))
            return
        }

        messages.append(ChatMessage(role: .user, text: text))

        switch provider.kind {
        case .desktop:
            AIRun.openDesktop(provider: provider, prompt: text)
            messages.append(ChatMessage(
                role: .system,
                text: l10n.t(.ai_desktopOpened, provider.name),
                providerID: provider.id
            ))
        case .cli:
            let msg = ChatMessage(role: .assistant, text: "", providerID: provider.id)
            messages.append(msg)
            let msgID = msg.id
            sending = true
            let proc = AIRun.streamCLI(
                provider: provider,
                prompt: text,
                settings: settings.data,
                onChunk: { chunk in
                    if let i = messages.firstIndex(where: { $0.id == msgID }) {
                        messages[i].text += chunk
                    }
                },
                onDone: { err in
                    sending = false
                    runningProcess = nil
                    if let err = err {
                        // Only surface error if we didn't get any output
                        if let i = messages.firstIndex(where: { $0.id == msgID }),
                           messages[i].text.isEmpty {
                            error = err.localizedDescription
                            messages.removeAll(where: { $0.id == msgID })
                        }
                    }
                }
            )
            runningProcess = proc

        case .api:
            sending = true
            let history = messages
                .filter { $0.role != .system }
                .map { ($0.role == .user ? "user" : "assistant", $0.text) }

            Task {
                do {
                    let reply: String
                    if provider.id == "claude-api" {
                        reply = try await AIRun.claudeAPI(
                            key: settings.data.claudeAPIKey,
                            model: settings.data.claudeModel,
                            history: history
                        )
                    } else {
                        reply = try await AIRun.openAIAPI(
                            key: settings.data.openaiAPIKey,
                            model: settings.data.openaiModel,
                            history: history
                        )
                    }
                    await MainActor.run {
                        messages.append(ChatMessage(role: .assistant, text: reply, providerID: provider.id))
                        sending = false
                    }
                } catch {
                    await MainActor.run {
                        self.error = error.localizedDescription
                        sending = false
                    }
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 30)
                Text(message.text)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.2))
                    )
                    .textSelection(.enabled)
            }
        case .assistant:
            HStack(alignment: .bottom, spacing: 6) {
                if message.text.isEmpty {
                    BrandPulse(size: 18)
                        .padding(.bottom, 3)
                }
                Text(message.text.isEmpty ? "..." : message.text)
                    .font(.system(size: 12, design: isCLIMessage ? .monospaced : .default))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.07))
                    )
                    .textSelection(.enabled)
                Spacer(minLength: 30)
            }
        case .system:
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        case .automation:
            AutomationRunBubble(title: message.text,
                                icon: iconFor(automationID: message.providerID),
                                run: message.automationRun)
        }
    }

    private func iconFor(automationID: String?) -> String {
        guard let id = automationID,
              let def = AutomationCatalog.all.first(where: { $0.id == id }) else {
            return "wand.and.stars"
        }
        return def.icon
    }

    private var isCLIMessage: Bool {
        guard let id = message.providerID else { return false }
        return id.hasSuffix("-cli") || id == "ollama"
    }
}

/// Rich inline bubble for an automation run (triggered from chat / chips /
/// slash). Animates from a "running" state (spinner + gradient pulse) to a
/// "done" state (status dot + stats strip).
struct AutomationRunBubble: View {
    let title: String
    let icon: String
    let run: AutomationRun?

    @State private var pulse = false

    var isRunning: Bool { run == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.2))
                        .frame(width: 22, height: 22)
                        .scaleEffect(isRunning && pulse ? 1.15 : 1.0)
                        .opacity(isRunning && pulse ? 0.5 : 1.0)
                    Image(systemName: isRunning ? icon : (run!.status == .succeeded ? "checkmark" : "xmark"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(statusColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(isRunning ? "Running…" : (run?.summary ?? ""))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if let run = run {
                    Text(formatDuration(run.duration))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            if let stats = run?.stats, !stats.isEmpty {
                HStack(spacing: 5) {
                    ForEach(stats, id: \.self) { s in
                        HStack(spacing: 3) {
                            Text(s.label).font(.system(size: 9)).foregroundStyle(.secondary)
                            Text(s.value).font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: NB.rMd, style: .continuous)
                .fill(statusColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NB.rMd, style: .continuous)
                .strokeBorder(statusColor.opacity(0.35), lineWidth: 0.6)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var statusColor: Color {
        guard let run = run else { return .blue }
        return run.status == .succeeded ? .green : .red
    }

    private func formatDuration(_ d: TimeInterval) -> String {
        if d < 1 { return String(format: "%.0fms", d * 1000) }
        if d < 60 { return String(format: "%.1fs", d) }
        return String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)
    }
}
