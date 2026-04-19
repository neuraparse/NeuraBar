import SwiftUI
import AppKit

struct RecordView: View {
    @EnvironmentObject var store: RecordingStore
    @EnvironmentObject var l10n: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            recorderButtons
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
        .animation(.spring(duration: 0.22, bounce: 0.15), value: store.isRecordingAudio)
        .animation(.spring(duration: 0.22, bounce: 0.15), value: store.isRecordingScreen)
    }

    // MARK: - Options panel

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

    // MARK: - Live level meter

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

    // MARK: - Recorder buttons

    private var recorderButtons: some View {
        HStack(spacing: 8) {
            recorderButton(
                active: store.isRecordingAudio,
                idleIcon: "mic.fill",
                activeIcon: "stop.fill",
                title: store.isRecordingAudio ? l10n.t(.record_stop) : l10n.t(.record_audioStart),
                color: .pink,
                action: {
                    store.isRecordingAudio ? store.stopAudio() : store.startAudio()
                }
            )
            .disabled(store.isRecordingScreen)

            recorderButton(
                active: store.isRecordingScreen,
                idleIcon: "rectangle.fill.on.rectangle.fill",
                activeIcon: "stop.fill",
                title: store.isRecordingScreen ? l10n.t(.record_stop) : l10n.t(.record_screenStart),
                color: .orange,
                action: {
                    store.isRecordingScreen ? store.stopScreen() : store.startScreen()
                }
            )
            .disabled(store.isRecordingAudio)
        }
    }

    private func recorderButton(
        active: Bool,
        idleIcon: String,
        activeIcon: String,
        title: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(active ? color : color.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: active ? activeIcon : idleIcon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(active ? .white : color)
                        .symbolEffect(.bounce, value: active)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    if active {
                        Text(RecordingStore.formatDuration(store.currentDuration))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    } else {
                        Text(l10n.t(.record_clickToStart))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if active {
                    RecordingPulse(color: color)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: NB.rMd, style: .continuous)
                    .fill(active ? color.opacity(0.12) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NB.rMd, style: .continuous)
                    .strokeBorder(active ? color.opacity(0.5) : Color.primary.opacity(0.05), lineWidth: 0.8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

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
