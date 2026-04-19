import SwiftUI
import AppKit

struct RecordView: View {
    @EnvironmentObject var store: RecordingStore
    @EnvironmentObject var l10n: Localization
    @EnvironmentObject var permissions: PermissionsStore
    @State private var showSourcePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PermissionsBanner(pane: .screenRecording)
                .environmentObject(permissions)
                .environmentObject(l10n)
            PermissionsBanner(pane: .microphone)
                .environmentObject(permissions)
                .environmentObject(l10n)
            primaryControls
            if store.isRecordingAudio {
                audioLevelMeter
            }
            optionsPanel
            if let err = store.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 2)
            }
            Divider().opacity(0.3)
            if store.recordings.isEmpty {
                EmptyState(icon: "waveform", text: l10n.t(.record_empty))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.recordings) { rec in
                            RecordingRow(rec: rec)
                                .environmentObject(store)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSourcePicker) {
            SourcePickerSheet { source in
                showSourcePicker = false
                startScreenRecording(source: source)
            }
            .environmentObject(l10n)
        }
        .animation(.spring(duration: 0.22, bounce: 0.15), value: store.isRecordingAudio)
        .animation(.spring(duration: 0.22, bounce: 0.15), value: store.isRecordingScreen)
    }

    // MARK: - Primary Start / Stop pills

    private var primaryControls: some View {
        HStack(spacing: 8) {
            audioPill
            screenPill
        }
    }

    private var audioPill: some View {
        let active = store.isRecordingAudio
        return Button {
            if active {
                store.stopAudio()
            } else {
                Task { @MainActor in
                    let state = await permissions.requestMicrophone()
                    if state == .authorized {
                        _ = store.startAudio()
                    }
                    // If denied, the banner at the top of the view already
                    // communicates next steps — no noisy alert here.
                }
            }
        } label: {
            pillLabel(
                active: active,
                idleIcon: "mic.fill",
                activeIcon: "stop.fill",
                title: active ? l10n.t(.record_stop) : l10n.t(.record_audioStart),
                duration: active ? RecordingStore.formatDuration(store.currentDuration) : nil,
                tint: .pink
            )
        }
        .buttonStyle(PressableStyle())
        .disabled(store.isRecordingScreen)
    }

    private var screenPill: some View {
        let active = store.isRecordingScreen
        return Button {
            if active {
                store.stopScreen()
            } else {
                showSourcePicker = true
            }
        } label: {
            pillLabel(
                active: active,
                idleIcon: "rectangle.on.rectangle",
                activeIcon: "stop.fill",
                title: active ? l10n.t(.record_stop) : l10n.t(.record_screenStart),
                duration: active ? RecordingStore.formatDuration(store.currentDuration) : nil,
                tint: .orange
            )
        }
        .buttonStyle(PressableStyle())
        .disabled(store.isRecordingAudio)
    }

    private func pillLabel(
        active: Bool,
        idleIcon: String,
        activeIcon: String,
        title: String,
        duration: String?,
        tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(active ? tint : tint.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: active ? activeIcon : idleIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(active ? .white : tint)
                    .symbolEffect(.bounce, value: active)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if let duration = duration {
                    Text(duration)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            Spacer()
            if active { RecordingPulse(color: tint) }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: NB.rMd, style: .continuous)
                .fill(active ? tint.opacity(0.12) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NB.rMd, style: .continuous)
                .strokeBorder(active ? tint.opacity(0.5) : Color.primary.opacity(0.05), lineWidth: 0.8)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Options

    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: $store.options.includeMicrophone) {
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill").font(.system(size: 9))
                    Text(l10n.t(.record_opt_mic)).font(.system(size: 11))
                }
            }
            .toggleStyle(.switch).controlSize(.mini)

            Toggle(isOn: $store.options.captureCursor) {
                HStack(spacing: 4) {
                    Image(systemName: "cursorarrow").font(.system(size: 9))
                    Text(l10n.t(.record_opt_cursor)).font(.system(size: 11))
                }
            }
            .toggleStyle(.switch).controlSize(.mini)

            Toggle(isOn: $store.options.postNotification) {
                HStack(spacing: 4) {
                    Image(systemName: "bell.fill").font(.system(size: 9))
                    Text(l10n.t(.record_opt_notify)).font(.system(size: 11))
                }
            }
            .toggleStyle(.switch).controlSize(.mini)

            if let mic = RecordingStore.currentMicrophoneName {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("\(l10n.t(.record_input)): \(mic)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Live audio level

    private var audioLevelMeter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.18))
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .red],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(2, geo.size.width * CGFloat(store.audioLevel)))
                    .animation(.linear(duration: 0.1), value: store.audioLevel)
            }
        }
        .frame(height: 5)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // MARK: - Start with source

    /// Guard on screen-recording permission only for the modes we actually
    /// capture ourselves. `.area` and `.systemPicker` both hand off to
    /// macOS's Screenshot.app, which has its own TCC prompt.
    private func startScreenRecording(source: RecordingSource) {
        let handsOffToOS = (source == .systemPicker || source == .area)
        if !handsOffToOS,
           permissions.screenRecording != .authorized {
            permissions.requestScreenRecording()
            return
        }
        WindowManager.shared.hideAllWindows()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            _ = store.startScreen(source: source)
        }
    }
}

// MARK: - Permission banner

struct PermissionsBanner: View {
    let pane: PermissionsService.PrivacyPane
    @EnvironmentObject var permissions: PermissionsStore
    @EnvironmentObject var l10n: Localization

    var body: some View {
        let render = shouldRender
        if render.visible {
            HStack(spacing: 8) {
                Image(systemName: render.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(render.tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: render.tint == .red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(render.title)
                        .font(.system(size: 11, weight: .semibold))
                    Text(render.body)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Button(action: render.action) {
                    Text(render.cta)
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(render.tint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(render.tint.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(render.tint.opacity(0.35), lineWidth: 0.6)
            )
            .transition(.opacity.combined(with: .offset(y: -4)))
        }
    }

    private struct Render {
        let visible: Bool
        let icon: String
        let tint: Color
        let title: String
        let body: String
        let cta: String
        let action: () -> Void
    }

    private var shouldRender: Render {
        switch pane {
        case .screenRecording:
            switch permissions.nextScreenRecordingAction {
            case .good:
                return Render(visible: false, icon: "", tint: .clear,
                              title: "", body: "", cta: "", action: {})
            case .request:
                return Render(
                    visible: true, icon: "rectangle.on.rectangle", tint: .orange,
                    title: l10n.t(.perm_screen_title),
                    body: l10n.t(.perm_screen_request_body),
                    cta: l10n.t(.perm_allow)
                ) { permissions.requestScreenRecording() }
            case .openSystemSettings:
                return Render(
                    visible: true, icon: "exclamationmark.triangle.fill", tint: .red,
                    title: l10n.t(.perm_screen_title),
                    body: l10n.t(.perm_screen_denied_body),
                    cta: l10n.t(.perm_openSettings)
                ) {
                    PermissionsService.openSystemSettings(for: .screenRecording)
                }
            case .restartNeuraBar:
                return Render(
                    visible: true, icon: "arrow.clockwise.circle.fill", tint: .blue,
                    title: l10n.t(.perm_restart_title),
                    body: l10n.t(.perm_restart_body),
                    cta: l10n.t(.perm_restart_cta)
                ) {
                    PermissionsService.restartApp()
                }
            }
        case .microphone:
            switch permissions.nextMicrophoneAction {
            case .good:
                return Render(visible: false, icon: "", tint: .clear,
                              title: "", body: "", cta: "", action: {})
            case .request:
                return Render(
                    visible: true, icon: "mic", tint: .orange,
                    title: l10n.t(.perm_mic_title),
                    body: l10n.t(.perm_mic_request_body),
                    cta: l10n.t(.perm_allow)
                ) {
                    Task { _ = await permissions.requestMicrophone() }
                }
            case .openSystemSettings:
                return Render(
                    visible: true, icon: "mic.slash", tint: .red,
                    title: l10n.t(.perm_mic_title),
                    body: l10n.t(.perm_mic_denied_body),
                    cta: l10n.t(.perm_openSettings)
                ) {
                    PermissionsService.openSystemSettings(for: .microphone)
                }
            }
        }
    }
}

// MARK: - Source picker sheet

struct SourcePickerSheet: View {
    @EnvironmentObject var l10n: Localization
    @Environment(\.dismiss) var dismiss
    let onPick: (RecordingSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(l10n.t(.record_src_title))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(l10n.t(.record_src_subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider().opacity(0.3)

            VStack(spacing: 8) {
                sourceTile(.fullScreen)
                sourceTile(.area)
                sourceTile(.systemPicker)
            }

            HStack {
                Spacer()
                Button(l10n.t(.cancel)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func sourceTile(_ source: RecordingSource) -> some View {
        Button {
            onPick(source)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: source.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t(source.titleKey))
                        .font(.system(size: 12, weight: .semibold))
                    Text(l10n.t(source.subtitleKey))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: NB.rMd, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NB.rMd, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Shared (pulse + row)

struct RecordingPulse: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(pulse ? 1.35 : 1.0)
            .opacity(pulse ? 0.4 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

struct RecordingRow: View {
    let rec: Recording
    @EnvironmentObject var store: RecordingStore
    @State private var hover = false

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.18))
                    .frame(width: 26, height: 26)
                Image(systemName: rec.kind == .audio ? "waveform" : "rectangle.on.rectangle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(rec.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(RecordingStore.formatDuration(rec.durationSeconds))
                        .font(.system(size: 9, design: .monospaced))
                    Text(RecordingStore.formatBytes(rec.sizeBytes))
                        .font(.system(size: 9))
                    Text(rec.createdAt, style: .relative)
                        .font(.system(size: 9))
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            if hover {
                Button {
                    store.reveal(rec)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(PressableStyle())
                Button {
                    store.delete(rec)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(hover ? 0.08 : 0.04))
        )
        .onHover { hover = $0 }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(rec.url)
        }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(rec.url) }
            Button("Reveal in Finder") { store.reveal(rec) }
            Divider()
            Button("Delete", role: .destructive) { store.delete(rec) }
        }
    }

    private var iconColor: Color {
        rec.kind == .audio ? .pink : .orange
    }
}
