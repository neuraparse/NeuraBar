import SwiftUI
import UserNotifications

final class PomodoroTimer: ObservableObject {
    enum Phase: String, Codable { case focus, shortBreak, longBreak, idle }

    @Published var phase: Phase = .idle
    @Published var remaining: Int = 25 * 60
    @Published var running: Bool = false
    @Published var sessionsCompleted: Int = 0

    var focusMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    var sessionsBeforeLongBreak: Int = 4

    private var timer: Timer?

    init() {
        // UserNotifications requires a proper .app bundle. When running inside
        // XCTest, Bundle.main is the xctest runner tool, not a .app — calling
        // requestAuthorization there throws NSInternalInconsistencyException.
        if Bundle.main.bundlePath.hasSuffix(".app") {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    var progress: Double {
        let total: Int = {
            switch phase {
            case .focus: return focusMinutes * 60
            case .shortBreak: return shortBreakMinutes * 60
            case .longBreak: return longBreakMinutes * 60
            case .idle: return focusMinutes * 60
            }
        }()
        return 1.0 - Double(remaining) / Double(total)
    }

    func startFocus() {
        phase = .focus
        remaining = focusMinutes * 60
        startTimer()
    }

    func startShortBreak() {
        phase = .shortBreak
        remaining = shortBreakMinutes * 60
        startTimer()
    }

    func startLongBreak() {
        phase = .longBreak
        remaining = longBreakMinutes * 60
        startTimer()
    }

    func pause() {
        running = false
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        if phase == .idle { startFocus() } else { startTimer() }
    }

    func reset() {
        pause()
        phase = .idle
        remaining = focusMinutes * 60
    }

    private func startTimer() {
        timer?.invalidate()
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.remaining > 0 {
                self.remaining -= 1
            } else {
                self.phaseFinished()
            }
        }
    }

    private func phaseFinished() {
        pause()
        notify(title: phase == .focus ? L.t(.focus_notif_focusDoneTitle) : L.t(.focus_notif_breakDoneTitle),
               body: phase == .focus ? L.t(.focus_notif_focusDoneBody) : L.t(.focus_notif_breakDoneBody))

        if phase == .focus {
            sessionsCompleted += 1
            if sessionsCompleted % sessionsBeforeLongBreak == 0 {
                startLongBreak()
            } else {
                startShortBreak()
            }
        } else {
            startFocus()
        }
    }

    private func notify(title: String, body: String) {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    var timeString: String {
        let m = remaining / 60
        let s = remaining % 60
        return String(format: "%02d:%02d", m, s)
    }
}

struct PomodoroView: View {
    @EnvironmentObject var timer: PomodoroTimer
    @EnvironmentObject var l10n: Localization

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 6)

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 10)

                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(
                        LinearGradient(colors: [.purple, .blue],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timer.progress)

                VStack(spacing: 4) {
                    Text(timer.timeString)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: timer.remaining)
                    Text(phaseLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .contentTransition(.identity)
                }
            }
            .frame(width: 180, height: 180)

            HStack(spacing: 10) {
                if timer.running {
                    actionButton("pause.fill", l10n.t(.focus_pause), .orange) { timer.pause() }
                } else {
                    actionButton("play.fill", timer.phase == .idle ? l10n.t(.focus_start) : l10n.t(.focus_resume), .accentColor) {
                        timer.resume()
                    }
                }
                actionButton("arrow.counterclockwise", l10n.t(.focus_reset), .secondary) { timer.reset() }
            }

            HStack(spacing: 20) {
                statBox(title: l10n.t(.focus_statToday), value: "\(timer.sessionsCompleted)")
                statBox(title: l10n.t(.focus_statNext), value: sessionsBeforeBreak)
            }

            Spacer()
        }
    }

    private var phaseLabel: String {
        switch timer.phase {
        case .focus: return l10n.t(.focus_state_focus)
        case .shortBreak: return l10n.t(.focus_state_shortBreak)
        case .longBreak: return l10n.t(.focus_state_longBreak)
        case .idle: return l10n.t(.focus_state_idle)
        }
    }

    private var sessionsBeforeBreak: String {
        let remaining = timer.sessionsBeforeLongBreak - (timer.sessionsCompleted % timer.sessionsBeforeLongBreak)
        return "\(remaining) \(l10n.t(.focus_sessionsSuffix))"
    }

    private func actionButton(_ icon: String, _ label: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(color.opacity(0.15))
            )
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    private func statBox(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
