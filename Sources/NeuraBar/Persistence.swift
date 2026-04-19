import Foundation
import SwiftUI
import ServiceManagement

enum Persistence {
    /// Tests set this to a temp dir so they don't pollute the real user state.
    nonisolated(unsafe) static var overrideDir: URL?

    /// Runtime override set by the Settings sheet when the user picks a new
    /// data location. Cleared on `resetDataLocation()`.
    nonisolated(unsafe) static var userDir: URL?

    static var supportDir: URL {
        if let override = overrideDir {
            if !FileManager.default.fileExists(atPath: override.path) {
                try? FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            }
            return override
        }
        if let user = userDir {
            if !FileManager.default.fileExists(atPath: user.path) {
                try? FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
            }
            return user
        }
        return DataLocationResolver.applicationSupportURL.also { dir in
            if !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    /// Called at launch + whenever the user changes the data location in
    /// Settings. Applies the new URL and returns the resolved path so the
    /// caller can show it in the UI.
    @discardableResult
    static func applyDataLocation(_ config: DataLocationConfig) -> URL {
        let url = DataLocationResolver.resolve(config)
        userDir = url
        return url
    }

    // MARK: - Bootstrap (location pointer)
    //
    // The data-location preference itself has to live somewhere that's
    // always reachable even before `supportDir` is resolved — otherwise
    // we can't know where to look for the rest of the data on launch.
    // `location.json` stays in Application Support forever; everything
    // else follows whichever URL it points at.

    private static var bootstrapURL: URL {
        let base = DataLocationResolver.applicationSupportURL
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base.appendingPathComponent("location.json")
    }

    static func loadDataLocation() -> DataLocationConfig {
        guard let data = try? Data(contentsOf: bootstrapURL),
              let cfg = try? JSONDecoder().decode(DataLocationConfig.self, from: data) else {
            return DataLocationConfig()
        }
        return cfg
    }

    static func saveDataLocation(_ config: DataLocationConfig) {
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: bootstrapURL, options: .atomic)
        }
    }

    static func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        let url = supportDir.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to file: String) {
        let url = supportDir.appendingPathComponent(file)
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Tiny Kotlin-style `also` on URL so we can create-on-access inline.
private extension URL {
    func also(_ block: (URL) -> Void) -> URL {
        block(self)
        return self
    }
}

struct SettingsStoreData: Codable {
    var claudeAPIKey: String = ""
    var claudeModel: String = "claude-sonnet-4-5"
    var openaiAPIKey: String = ""
    var openaiModel: String = "gpt-4o-mini"
    var ollamaModel: String = "llama3.2"
    var preferredProviderID: String = ""
    var accentColorHex: String = "#7C3AED"
    var language: SupportedLanguage = .auto

    init() {}

    // Tolerant decoder: missing keys fall back to the default value so that
    // existing settings.json files keep working after new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        claudeAPIKey = (try? c.decode(String.self, forKey: .claudeAPIKey)) ?? ""
        claudeModel = (try? c.decode(String.self, forKey: .claudeModel)) ?? "claude-sonnet-4-5"
        openaiAPIKey = (try? c.decode(String.self, forKey: .openaiAPIKey)) ?? ""
        openaiModel = (try? c.decode(String.self, forKey: .openaiModel)) ?? "gpt-4o-mini"
        ollamaModel = (try? c.decode(String.self, forKey: .ollamaModel)) ?? "llama3.2"
        preferredProviderID = (try? c.decode(String.self, forKey: .preferredProviderID)) ?? ""
        accentColorHex = (try? c.decode(String.self, forKey: .accentColorHex)) ?? "#7C3AED"
        language = (try? c.decode(SupportedLanguage.self, forKey: .language)) ?? .auto
    }
}

final class SettingsStore: ObservableObject {
    @Published var data: SettingsStoreData {
        didSet { Persistence.save(data, to: "settings.json") }
    }

    init() {
        self.data = Persistence.load(SettingsStoreData.self, from: "settings.json") ?? SettingsStoreData()
    }
}

// MARK: - Launch at login (SMAppService, macOS 13+)

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}

// MARK: - Settings Sheet

enum SettingsTab: String, CaseIterable, Identifiable {
    case ai, general, about
    var id: String { rawValue }
    var titleKey: Loc {
        switch self {
        case .ai: return .set_ai
        case .general: return .set_general
        case .about: return .set_about
        }
    }
    var icon: String {
        switch self {
        case .ai: return "sparkles"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var l10n: Localization
    @Environment(\.dismiss) var dismiss

    @State private var tab: SettingsTab = .ai
    @State private var tempClaudeKey: String = ""
    @State private var tempClaudeModel: String = ""
    @State private var tempOpenAIKey: String = ""
    @State private var tempOpenAIModel: String = ""
    @State private var tempOllamaModel: String = ""
    @State private var tempLanguage: SupportedLanguage = .auto
    @State private var launchAtLogin: Bool = false
    @State private var launchError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)

            // Horizontal tab strip (fits narrow popovers — sidebar got clipped inside
            // MenuBarExtra's 420px popover so General/About were unreachable).
            tabStrip
            Divider().opacity(0.3)

            Group {
                switch tab {
                case .ai: aiPanel
                case .general: generalPanel
                case .about: aboutPanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 4)),
                removal: .opacity
            ))
            .id(tab)
            .animation(.spring(duration: 0.22, bounce: 0.1), value: tab)

            Divider().opacity(0.3)
            footer
        }
        .frame(width: NB.panelWidth, height: NB.panelHeight)
        .background(.ultraThinMaterial)
        .onAppear(perform: loadState)
    }

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { t in
                let selected = tab == t
                Button {
                    withAnimation(.spring(duration: 0.26, bounce: 0.15)) { tab = t }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: t.icon)
                            .font(.system(size: 11, weight: .medium))
                        Text(l10n.t(t.titleKey))
                            .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    }
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
            Spacer()
        }
        .padding(.horizontal, NB.sp4)
        .padding(.vertical, NB.sp2)
    }

    // MARK: - Layout pieces

    private var header: some View {
        HStack {
            Text(l10n.t(.set_title))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .nbHoverHighlight(cornerRadius: 5, intensity: 0.1)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, NB.sp5)
        .padding(.vertical, NB.sp3)
    }

    private var aiPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                aiProviderCard(
                    title: l10n.t(.set_anthropic),
                    icon: "sparkle",
                    color: .purple,
                    key: $tempClaudeKey,
                    keyPlaceholder: "sk-ant-...",
                    model: $tempClaudeModel,
                    modelPlaceholder: "claude-sonnet-4-5",
                    linkURL: URL(string: "https://console.anthropic.com/settings/keys")!
                )

                aiProviderCard(
                    title: l10n.t(.set_openai),
                    icon: "brain",
                    color: .green,
                    key: $tempOpenAIKey,
                    keyPlaceholder: "sk-...",
                    model: $tempOpenAIModel,
                    modelPlaceholder: "gpt-4o-mini",
                    linkURL: URL(string: "https://platform.openai.com/api-keys")!
                )

                ollamaCard
            }
            .padding(NB.sp5)
        }
    }

    private var ollamaCard: some View {
        VStack(alignment: .leading, spacing: NB.sp2) {
            HStack(spacing: 6) {
                Image(systemName: "cpu.fill").foregroundStyle(.teal)
                Text(l10n.t(.set_ollama))
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(l10n.t(.set_ollamaHint))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("llama3.2", text: $tempOllamaModel)
                .textFieldStyle(.roundedBorder)
            Link("ollama.com →", destination: URL(string: "https://ollama.com")!)
                .font(.caption)
        }
        .padding(NB.sp4)
        .nbCard()
    }

    private func aiProviderCard(
        title: String, icon: String, color: Color,
        key: Binding<String>, keyPlaceholder: String,
        model: Binding<String>, modelPlaceholder: String,
        linkURL: URL
    ) -> some View {
        VStack(alignment: .leading, spacing: NB.sp2) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !key.wrappedValue.isEmpty {
                    HStack(spacing: 3) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text(l10n.t(.set_active)).font(.system(size: 10, weight: .medium)).foregroundStyle(.green)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.t(.set_apiKey)).font(.caption2).foregroundStyle(.secondary)
                SecureField(keyPlaceholder, text: key)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.t(.set_model)).font(.caption2).foregroundStyle(.secondary)
                TextField(modelPlaceholder, text: model)
                    .textFieldStyle(.roundedBorder)
            }
            Link(l10n.t(.set_getApiKey) + " →", destination: linkURL)
                .font(.caption)
        }
        .padding(NB.sp4)
        .nbCard()
    }

    private var generalPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Language
                VStack(alignment: .leading, spacing: NB.sp2) {
                    Text(l10n.t(.set_language))
                        .font(.system(size: 13, weight: .semibold))
                    Text(l10n.t(.set_language_body))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $tempLanguage) {
                        ForEach(SupportedLanguage.allCases) { lang in
                            Text(lang.label).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: tempLanguage) { _, newValue in
                        settings.data.language = newValue
                        Localization.shared.apply(override: newValue)
                    }
                }
                .padding(NB.sp4)
                .nbCard()

                // Launch at login
                VStack(alignment: .leading, spacing: NB.sp2) {
                    Toggle(isOn: $launchAtLogin) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l10n.t(.set_launch_title)).font(.system(size: 13, weight: .medium))
                            Text(l10n.t(.set_launch_body))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            try LaunchAtLogin.set(newValue)
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                    if let err = launchError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(NB.sp4)
                .nbCard()

                DataLocationCard()
                    .environmentObject(l10n)

                // Shortcuts
                VStack(alignment: .leading, spacing: NB.sp2) {
                    Text(l10n.t(.set_shortcuts))
                        .font(.system(size: 13, weight: .semibold))
                    shortcutRow(GlobalHotkey.shared.binding.humanReadable, l10n.t(.set_sc_global))
                    shortcutRow("⌘K", l10n.t(.set_sc_palette))
                    shortcutRow("⌘,", l10n.t(.set_sc_settings))
                    shortcutRow("⌘1 – ⌘9", l10n.t(.set_sc_tabs))
                    shortcutRow("⌘Q", l10n.t(.set_sc_quit))
                }
                .padding(NB.sp4)
                .nbCard()
            }
            .padding(NB.sp5)
        }
    }

    private func shortcutRow(_ keys: String, _ desc: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
            Text(desc).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var aboutPanel: some View {
        VStack(spacing: NB.sp5) {
            Spacer()
            LogoView(size: 72)
            VStack(spacing: 3) {
                Text(l10n.t(.appName)).font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(l10n.t(.about_version, "1.3.0")).font(.caption).foregroundStyle(.secondary)
            }
            Text(l10n.t(.about_description))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Link("github.com/bayrameker →", destination: URL(string: "https://github.com/bayrameker")!)
                .font(.caption)
            Spacer()
            Text(l10n.t(.about_copyright))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, NB.sp3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if tab == .ai {
                Text(l10n.t(.set_aiDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if tab == .general {
                Text(l10n.t(.set_autoSaveNote))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if tab == .ai {
                Button(l10n.t(.cancel)) { dismiss() }
                Button(l10n.t(.save)) {
                    saveAI()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            } else {
                Button(l10n.t(.close)) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, NB.sp5)
        .padding(.vertical, NB.sp3)
    }

    // MARK: - Actions

    private func loadState() {
        tempClaudeKey = settings.data.claudeAPIKey
        tempClaudeModel = settings.data.claudeModel
        tempOpenAIKey = settings.data.openaiAPIKey
        tempOpenAIModel = settings.data.openaiModel
        tempOllamaModel = settings.data.ollamaModel
        tempLanguage = settings.data.language
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    private func saveAI() {
        settings.data.claudeAPIKey = tempClaudeKey
        settings.data.claudeModel = tempClaudeModel.isEmpty ? "claude-sonnet-4-5" : tempClaudeModel
        settings.data.openaiAPIKey = tempOpenAIKey
        settings.data.openaiModel = tempOpenAIModel.isEmpty ? "gpt-4o-mini" : tempOpenAIModel
        settings.data.ollamaModel = tempOllamaModel.isEmpty ? "llama3.2" : tempOllamaModel
    }
}
