import Foundation
import AppKit

enum AIProviderKind: String, Codable {
    case cli
    case api
    case desktop
}

struct AIProvider: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let kind: AIProviderKind
    var executablePath: String? = nil
    var bundlePath: String? = nil
    var needsKey: Bool = false

    static func == (a: AIProvider, b: AIProvider) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum AIDetector {
    // Session cache — avoid spawning login-shell zsh subprocess for every
    // missing binary on every AI tab open. `detect()` loops over 10+ CLI names,
    // and without this cache each open takes ~0.5–1.2 s on a machine missing
    // most of them.
    nonisolated(unsafe) private static var whichCache: [String: String?] = [:]
    private static let whichCacheLock = NSLock()

    /// Clears the which() cache so the next detect() re-scans from scratch.
    /// Wire to the manual "Refresh" button.
    static func invalidateWhichCache() {
        whichCacheLock.lock()
        whichCache.removeAll()
        whichCacheLock.unlock()
    }

    /// Search common locations for a CLI binary. PATH is often empty in bundled
    /// GUI apps. Pass `useCache: false` to force a fresh probe.
    static func which(_ name: String, useCache: Bool = true) -> String? {
        if useCache {
            whichCacheLock.lock()
            if let cached = whichCache[name] {
                whichCacheLock.unlock()
                return cached
            }
            whichCacheLock.unlock()
        }

        let result = whichUncached(name)

        whichCacheLock.lock()
        whichCache[name] = result
        whichCacheLock.unlock()
        return result
    }

    private static func whichUncached(_ name: String) -> String? {
        // `name` only ever comes from the hardcoded cliDefs list, but guard
        // anyway: it's interpolated into a zsh `command -v` below, so a name
        // with shell metacharacters must never reach that path.
        guard name.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { return nil }
        let candidates = [
            "/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin",
            NSString("~/.local/bin").expandingTildeInPath,
            NSString("~/.cargo/bin").expandingTildeInPath,
            NSString("~/.bun/bin").expandingTildeInPath,
            NSString("~/bin").expandingTildeInPath,
            NSString("~/.volta/bin").expandingTildeInPath,
            NSString("~/n/bin").expandingTildeInPath,
            "/opt/local/bin"
        ]
        for dir in candidates {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        // Fall back to a login shell which() — works if user has a non-trivial PATH
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-l", "-c", "command -v \(name)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !str.isEmpty, FileManager.default.isExecutableFile(atPath: str) { return str }
        } catch { /* ignore */ }
        return nil
    }

    static func app(bundleID: String) -> String? {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            return url.path
        }
        return nil
    }

    /// Return the full list of available providers, in preferred order.
    static func detect(settings: SettingsStoreData) -> [AIProvider] {
        var out: [AIProvider] = []

        // --- CLI tools (highest priority — local, free, streams) ---
        // See 2026 coding-CLI landscape: Claude Code, Codex, Aider, opencode,
        // Gemini, Amp, Goose, Qwen Code, Plandex, Continue, Ollama, …
        let cliDefs: [(id: String, binary: String, name: String, subtitle: String, icon: String)] = [
            ("claude-cli", "claude",     "Claude Code", "Anthropic coding agent",  "terminal.fill"),
            ("codex-cli",  "codex",      "Codex CLI",    "OpenAI coding agent",     "terminal"),
            ("aider-cli",  "aider",      "Aider",        "Pair programmer",         "person.2"),
            ("opencode-cli", "opencode", "opencode",     "OSS multi-provider",      "chevron.left.chevron.right"),
            ("gemini-cli", "gemini",     "Gemini CLI",   "Google, 1M context",      "terminal"),
            ("amp-cli",    "amp",        "Amp",          "Sourcegraph",             "terminal"),
            ("goose-cli",  "goose",      "Goose",        "Block open-source",       "bird"),
            ("qwen-cli",   "qwen-code",  "Qwen Code",    "Alibaba",                 "terminal"),
            ("plandex-cli","plandex",    "Plandex",      "Terminal planner",        "list.bullet.clipboard"),
            ("continue-cli","continue",  "Continue",     "Continue.dev",            "arrow.right.circle")
        ]
        for def in cliDefs {
            if let p = which(def.binary) {
                out.append(AIProvider(
                    id: def.id,
                    name: def.name,
                    subtitle: def.subtitle,
                    icon: def.icon,
                    kind: .cli,
                    executablePath: p
                ))
            }
        }

        if let p = which("ollama") {
            out.append(AIProvider(
                id: "ollama",
                name: "Ollama",
                subtitle: "Local · \(settings.ollamaModel)",
                icon: "cpu.fill",
                kind: .cli,
                executablePath: p
            ))
        }

        // --- Direct APIs ---
        if !settings.claudeAPIKey.isEmpty {
            out.append(AIProvider(
                id: "claude-api",
                name: "Claude API",
                subtitle: settings.claudeModel,
                icon: "sparkles",
                kind: .api
            ))
        }
        if !settings.openaiAPIKey.isEmpty {
            out.append(AIProvider(
                id: "openai-api",
                name: "OpenAI API",
                subtitle: settings.openaiModel,
                icon: "brain",
                kind: .api
            ))
        }

        // --- Desktop apps (handoff — opens the app with the prompt) ---
        if let p = app(bundleID: "com.anthropic.claudefordesktop") {
            out.append(AIProvider(
                id: "claude-desktop",
                name: "Claude Desktop",
                subtitle: L.t(.ai_openInApp),
                icon: "macwindow",
                kind: .desktop,
                bundlePath: p
            ))
        }
        if let p = app(bundleID: "com.openai.chat") {
            out.append(AIProvider(
                id: "chatgpt-desktop",
                name: "ChatGPT",
                subtitle: L.t(.ai_openInApp),
                icon: "macwindow",
                kind: .desktop,
                bundlePath: p
            ))
        }
        if let p = app(bundleID: "com.openai.codex") {
            out.append(AIProvider(
                id: "codex-desktop",
                name: "Codex",
                subtitle: L.t(.ai_openInApp),
                icon: "macwindow",
                kind: .desktop,
                bundlePath: p
            ))
        }
        if let p = app(bundleID: "com.openai.atlas") {
            out.append(AIProvider(
                id: "atlas-desktop",
                name: "ChatGPT Atlas",
                subtitle: L.t(.ai_openInApp),
                icon: "macwindow",
                kind: .desktop,
                bundlePath: p
            ))
        }

        return out
    }
}

// MARK: - Running

enum AIRun {
    /// Stream output from a CLI-backed provider. `onChunk` is called on the main actor.
    static func streamCLI(
        provider: AIProvider,
        prompt: String,
        settings: SettingsStoreData,
        onChunk: @escaping @MainActor (String) -> Void,
        onDone: @escaping @MainActor (Error?) -> Void
    ) -> Process? {
        guard let exe = provider.executablePath else {
            Task { @MainActor in onDone(NSError(domain: "AIRun", code: 1, userInfo: [NSLocalizedDescriptionKey: "CLI bulunamadı"])) }
            return nil
        }

        let task = Process()
        task.launchPath = exe

        switch provider.id {
        case "claude-cli":        task.arguments = ["-p", prompt]
        case "codex-cli":         task.arguments = ["exec", prompt]
        case "ollama":            task.arguments = ["run", settings.ollamaModel, prompt]
        case "gemini-cli":        task.arguments = ["-p", prompt]
        // 2026 coding CLIs
        case "opencode-cli":      task.arguments = ["-p", prompt, "-q"]
        case "aider-cli":         task.arguments = ["--message", prompt, "--no-pretty", "--yes-always"]
        case "amp-cli":           task.arguments = ["-p", prompt]
        case "goose-cli":         task.arguments = ["run", "-t", prompt]
        case "qwen-cli":          task.arguments = ["-p", prompt]
        case "plandex-cli":       task.arguments = ["tell", prompt]
        case "continue-cli":      task.arguments = ["-p", prompt]
        default:                  task.arguments = [prompt]
        }

        // Ensure a sane PATH for subprocesses
        var env = ProcessInfo.processInfo.environment
        let extraPath = "/usr/local/bin:/opt/homebrew/bin:\(NSString("~/.local/bin").expandingTildeInPath)"
        env["PATH"] = (env["PATH"] ?? "") + ":" + extraPath
        task.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        // Streaming reads arrive on arbitrary 16–64KB boundaries that can split
        // a multi-byte UTF-8 sequence (common with Turkish text / emoji / box
        // chars). Buffer raw bytes and only emit once the buffer decodes
        // cleanly, holding back a partial trailing char until the next read —
        // otherwise those bytes were silently dropped.
        var stdoutPending = Data()
        var stderrAccum = ""

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            stdoutPending.append(data)
            if let s = String(data: stdoutPending, encoding: .utf8) {
                stdoutPending.removeAll(keepingCapacity: true)
                if !s.isEmpty { Task { @MainActor in onChunk(s) } }
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let s = String(data: data, encoding: .utf8) {
                // Strip ANSI escapes (spinners/colors) but keep real error text
                // so we can surface it when the process exits non-zero.
                let cleaned = s.replacingOccurrences(
                    of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression
                )
                if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    stderrAccum += cleaned
                }
            }
        }

        task.terminationHandler = { proc in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            // Flush any trailing buffered bytes.
            if !stdoutPending.isEmpty,
               let s = String(data: stdoutPending, encoding: .utf8), !s.isEmpty {
                Task { @MainActor in onChunk(s) }
            }
            let err: Error?
            if proc.terminationStatus == 0 {
                err = nil
            } else {
                // Surface the actual stderr tail instead of a bare exit code.
                let detail = stderrAccum.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = detail.isEmpty ? "" : ": " + String(detail.suffix(500))
                err = NSError(domain: "AIRun", code: Int(proc.terminationStatus),
                              userInfo: [NSLocalizedDescriptionKey: "CLI exited with code \(proc.terminationStatus)\(suffix)"])
            }
            Task { @MainActor in onDone(err) }
        }

        do {
            try task.run()
            return task
        } catch {
            Task { @MainActor in onDone(error) }
            return nil
        }
    }

    /// Hand off the prompt to a desktop app. Copies prompt to clipboard and opens the app.
    @MainActor
    static func openDesktop(provider: AIProvider, prompt: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(prompt, forType: .string)
        if let path = provider.bundlePath {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    /// One-shot Claude API call.
    static func claudeAPI(key: String, model: String, history: [(String, String)]) async throws -> String {
        guard !key.isEmpty else {
            throw NSError(domain: "AIRun", code: 401, userInfo: [NSLocalizedDescriptionKey: "Claude API anahtarı yok"])
        }
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        req.timeoutInterval = 45

        let messages = history.map { ["role": $0.0, "content": $0.1] }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": messages
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "AIRun", code: (resp as? HTTPURLResponse)?.statusCode ?? 0,
                          userInfo: [NSLocalizedDescriptionKey: text])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw NSError(domain: "AIRun", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "Beklenmeyen cevap"])
        }
        // Concatenate every text block — 2026 models may prepend a thinking /
        // tool_use block before the text, so `content.first` isn't reliable.
        let text = content
            .compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
            .joined()
        guard !text.isEmpty else {
            throw NSError(domain: "AIRun", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "Beklenmeyen cevap"])
        }
        return text
    }

    /// One-shot OpenAI Chat Completions call.
    static func openAIAPI(key: String, model: String, history: [(String, String)]) async throws -> String {
        guard !key.isEmpty else {
            throw NSError(domain: "AIRun", code: 401, userInfo: [NSLocalizedDescriptionKey: "OpenAI API anahtarı yok"])
        }
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 45

        let messages = history.map { ["role": $0.0, "content": $0.1] }
        let body: [String: Any] = [
            "model": model,
            "messages": messages
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "AIRun", code: (resp as? HTTPURLResponse)?.statusCode ?? 0,
                          userInfo: [NSLocalizedDescriptionKey: text])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw NSError(domain: "AIRun", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "Beklenmeyen cevap"])
        }
        return text
    }
}
