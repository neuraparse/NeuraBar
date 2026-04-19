import SwiftUI
import UserNotifications

// MARK: - Mode presets

enum PomodoroMode: String, CaseIterable, Codable, Identifiable {
    case classic, extended, short, deep, custom
    var id: String { rawValue }

    var focus: Int {
        switch self {
        case .classic: return 25
        case .extended: return 50
        case .short: return 15
        case .deep: return 90
        case .custom: return 25
        }
    }

    var shortBreak: Int {
        switch self {
        case .classic: return 5
        case .extended: return 10
        case .short: return 3
        case .deep: return 20
        case .custom: return 5
        }
    }

    var longBreak: Int {
        switch self {
        case .classic: return 15
        case .extended: return 30
        case .short: return 10
        case .deep: return 45
        case .custom: return 15
        }
    }

    var labelKey: Loc {
        switch self {
        case .classic: return .focus_mode_classic
        case .extended: return .focus_mode_extended
        case .short: return .focus_mode_short
        case .deep: return .focus_mode_deep
        case .custom: return .focus_mode_custom
        }
    }
}

// MARK: - Session record

struct PomodoroSession: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let phase: String
    let startedAt: Date
    let endedAt: Date

    var durationSeconds: Int { Int(endedAt.timeIntervalSince(startedAt)) }
    var durationMinutes: Int { max(1, Int((Double(durationSeconds) / 60.0).rounded())) }
}

// MARK: - Timer

final class PomodoroTimer: ObservableObject {
    enum Phase: String, Codable { case focus, shortBreak, longBreak, idle }

    // Live state
    @Published var phase: Phase = .idle
    @Published var remaining: Int = 25 * 60
    @Published var running: Bool = false
    @Published var sessionsCompleted: Int = 0

    // Config (persisted)
    @Published var mode: PomodoroMode = .classic {
        didSet {
            if !running && phase == .idle { applyModeDurations() }
            persistConfig()
        }
    }
    @Published var customFocusMinutes: Int = 25 { didSet { persistConfig() } }
    @Published var customShortBreakMinutes: Int = 5 { didSet { persistConfig() } }
    @Published var customLongBreakMinutes: Int = 15 { didSet { persistConfig() } }
    @Published var autoStartBreak: Bool = true { didSet { persistConfig() } }
    @Published var autoStartNextFocus: Bool = false { didSet { persistConfig() } }
    @Published var dailyGoal: Int = 4 { didSet { persistConfig() } }

    // History (persisted)
    @Published var sessions: [PomodoroSession] = [] {
        didSet { Persistence.save(sessions, to: "pomodoro_sessions.json") }
    }

    // Working state
    var sessionsBeforeLongBreak: Int = 4
    private var currentStart: Date?
    private var timer: Timer?

    private struct Config: Codable {
        var mode: PomodoroMode
        var customFocus: Int
        var customShortBreak: Int
        var customLongBreak: Int
        var autoStartBreak: Bool
        var autoStartNextFocus: Bool
        var dailyGoal: Int
        var sessionsCompleted: Int
    }

    init() {
        if Bundle.main.bundlePath.hasSuffix(".app") {
            UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        if let cfg = Persistence.load(Config.self, from: "pomodoro_config.json") {
            self.mode = cfg.mode
            self.customFocusMinutes = cfg.customFocus
            self.customShortBreakMinutes = cfg.customShortBreak
            self.customLongBreakMinutes = cfg.customLongBreak
            self.autoStartBreak = cfg.autoStartBreak
            self.autoStartNextFocus = cfg.autoStartNextFocus
            self.dailyGoal = cfg.dailyGoal
            self.sessionsCompleted = cfg.sessionsCompleted
        }
        if let s = Persistence.load([PomodoroSession].self, from: "pomodoro_sessions.json") {
            self.sessions = s
        }
        applyModeDurations()
    }

    private func persistConfig() {
        let cfg = Config(
            mode: mode,
            customFocus: customFocusMinutes,
            customShortBreak: customShortBreakMinutes,
            customLongBreak: customLongBreakMinutes,
            autoStartBreak: autoStartBreak,
            autoStartNextFocus: autoStartNextFocus,
            dailyGoal: dailyGoal,
            sessionsCompleted: sessionsCompleted
        )
        Persistence.save(cfg, to: "pomodoro_config.json")
    }

    // MARK: - Mode-derived durations

    var focusMinutes: Int {
        mode == .custom ? customFocusMinutes : mode.focus
    }
    var shortBreakMinutes: Int {
        mode == .custom ? customShortBreakMinutes : mode.shortBreak
    }
    var longBreakMinutes: Int {
        mode == .custom ? customLongBreakMinutes : mode.longBreak
    }

    private func applyModeDurations() {
        if phase == .idle {
            remaining = focusMinutes * 60
        }
    }

    // MARK: - Progress

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

    var timeString: String {
        let m = remaining / 60
        let s = remaining % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Controls

    func startFocus() {
        phase = .focus
        remaining = focusMinutes * 60
        currentStart = Date()
        startTimer()
    }

    func startShortBreak() {
        phase = .shortBreak
        remaining = shortBreakMinutes * 60
        currentStart = Date()
        startTimer()
    }

    func startLongBreak() {
        phase = .longBreak
        remaining = longBreakMinutes * 60
        currentStart = Date()
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
        currentStart = nil
        remaining = focusMinutes * 60
    }

    /// Skip the current phase — advance the state machine as if it finished.
    func skip() {
        guard phase != .idle else { return }
        remaining = 0
        phaseFinished()
    }

    /// Extend remaining time by N minutes (capped at 60 per call).
    func extend(minutes: Int) {
        let delta = max(0, min(60, minutes)) * 60
        remaining += delta
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
        if let start = currentStart {
            sessions.insert(PomodoroSession(
                phase: phase.rawValue,
                startedAt: start,
                endedAt: Date()
            ), at: 0)
            if sessions.count > 500 {
                sessions = Array(sessions.prefix(500))
            }
        }
        currentStart = nil

        notify(
            title: phase == .focus ? L.t(.focus_notif_focusDoneTitle) : L.t(.focus_notif_breakDoneTitle),
            body: phase == .focus ? L.t(.focus_notif_focusDoneBody) : L.t(.focus_notif_breakDoneBody)
        )

        let finishedFocus = phase == .focus
        if finishedFocus {
            sessionsCompleted += 1
            persistConfig()
        }

        let isLong = finishedFocus && (sessionsCompleted % sessionsBeforeLongBreak == 0)
        if finishedFocus {
            if autoStartBreak {
                isLong ? startLongBreak() : startShortBreak()
            } else {
                phase = .idle
                remaining = (isLong ? longBreakMinutes : shortBreakMinutes) * 60
            }
        } else {
            if autoStartNextFocus {
                startFocus()
            } else {
                phase = .idle
                remaining = focusMinutes * 60
            }
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

    // MARK: - Stats (pure, testable)

    func sessionsToday(now: Date = Date()) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        return sessions.filter {
            $0.phase == Phase.focus.rawValue && $0.startedAt >= start
        }.count
    }

    func focusMinutesToday(now: Date = Date()) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        return sessions
            .filter { $0.phase == Phase.focus.rawValue && $0.startedAt >= start }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    /// Consecutive days (ending today) with at least one focus session.
    func streakDays(now: Date = Date()) -> Int {
        let cal = Calendar.current
        var days = Set<Date>()
        for s in sessions where s.phase == Phase.focus.rawValue {
            days.insert(cal.startOfDay(for: s.startedAt))
        }
        var streak = 0
        var cursor = cal.startOfDay(for: now)
        while days.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }
}

// MARK: - View

struct PomodoroView: View {
    @EnvironmentObject var timer: PomodoroTimer
    @EnvironmentObject var l10n: Localization

    @State private var showCustomSheet = false

    var body: some View {
        GeometryReader { geo in
            let isBig = geo.size.width >= 520
            ScrollView {
                VStack(spacing: isBig ? 18 : 12) {
                    modePicker
                    timerDial(big: isBig)
                    controls
                    contextualActions
                    statsPanel
                    autoToggles
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        }
        .sheet(isPresented: $showCustomSheet) {
            CustomDurationSheet()
                .environmentObject(timer)
                .environmentObject(l10n)
        }
    }

    // MARK: Mode picker

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(PomodoroMode.allCases) { mode in
                let active = timer.mode == mode
                Button {
                    withAnimation(.spring(duration: 0.22, bounce: 0.2)) {
                        timer.mode = mode
                    }
                    if mode == .custom { showCustomSheet = true }
                } label: {
                    Text(l10n.t(mode.labelKey))
                        .font(.system(size: 10, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? Color.accentColor : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(active ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                        )
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: Timer dial

    private func timerDial(big: Bool) -> some View {
        let size: CGFloat = big ? 240 : 180
        let lineWidth: CGFloat = big ? 14 : 10
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: timer.progress)
                .stroke(
                    LinearGradient(
                        colors: phaseGradient,
                        startPoint: .top, endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: timer.progress)
                .animation(.spring(duration: 0.45, bounce: 0.25), value: timer.phase)

            VStack(spacing: big ? 6 : 4) {
                Text(timer.timeString)
                    .font(.system(size: big ? 56 : 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: timer.remaining)
                Text(phaseLabel)
                    .font(big ? .callout : .caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.8)
                if timer.running, timer.remaining > 0 {
                    Text(etaLabel)
                        .font(.system(size: big ? 11 : 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private var phaseGradient: [Color] {
        switch timer.phase {
        case .focus, .idle: return [.purple, .blue]
        case .shortBreak: return [.green, .mint]
        case .longBreak: return [.teal, .cyan]
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

    private var etaLabel: String {
        let ends = Date().addingTimeInterval(TimeInterval(timer.remaining))
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return "\(l10n.t(.focus_endsAt)) \(df.string(from: ends))"
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            if timer.running {
                actionButton("pause.fill", l10n.t(.focus_pause), .orange) { timer.pause() }
            } else {
                actionButton(
                    "play.fill",
                    timer.phase == .idle ? l10n.t(.focus_start) : l10n.t(.focus_resume),
                    .accentColor
                ) { timer.resume() }
            }
            actionButton("arrow.counterclockwise", l10n.t(.focus_reset), .secondary) {
                timer.reset()
            }
        }
    }

    @ViewBuilder
    private var contextualActions: some View {
        if timer.phase != .idle {
            HStack(spacing: 8) {
                smallButton(icon: "forward.end.fill", label: l10n.t(.focus_skip)) {
                    timer.skip()
                }
                smallButton(icon: "plus.circle", label: l10n.t(.focus_extend5)) {
                    timer.extend(minutes: 5)
                }
            }
            .transition(.opacity.combined(with: .offset(y: 4)))
        }
    }

    // MARK: Stats

    private var statsPanel: some View {
        HStack(spacing: 8) {
            statBox(
                icon: "flame.fill", color: .orange,
                value: "\(timer.streakDays())",
                label: l10n.t(.focus_stat_streak)
            )
            statBox(
                icon: "checkmark.circle.fill", color: .green,
                value: "\(timer.sessionsToday())",
                label: l10n.t(.focus_stat_sessionsToday)
            )
            statBox(
                icon: "clock.fill", color: .blue,
                value: "\(timer.focusMinutesToday())m",
                label: l10n.t(.focus_stat_focusTime)
            )
            goalRing
        }
        .padding(.horizontal, 4)
    }

    private func statBox(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var goalRing: some View {
        let done = timer.sessionsToday()
        let goal = max(1, timer.dailyGoal)
        let fraction = min(1.0, Double(done) / Double(goal))
        return VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: fraction)
                Text("\(done)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
            }
            .frame(width: 28, height: 28)
            Text("/ \(goal)")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: Auto toggles

    private var autoToggles: some View {
        VStack(spacing: 4) {
            toggleRow(l10n.t(.focus_autoBreak), isOn: $timer.autoStartBreak)
            toggleRow(l10n.t(.focus_autoFocus), isOn: $timer.autoStartNextFocus)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04))
        )
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.system(size: 11))
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }

    // MARK: Helpers

    private func actionButton(_ icon: String, _ label: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .symbolEffect(.bounce, value: timer.running)
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(color.opacity(0.15))
            )
            .foregroundStyle(color)
        }
        .buttonStyle(PressableStyle())
    }

    private func smallButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Custom duration sheet

struct CustomDurationSheet: View {
    @EnvironmentObject var timer: PomodoroTimer
    @EnvironmentObject var l10n: Localization
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.t(.focus_custom_title))
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            stepperRow(
                title: l10n.t(.focus_custom_focus),
                value: $timer.customFocusMinutes,
                range: 5...180
            )
            stepperRow(
                title: l10n.t(.focus_custom_shortBreak),
                value: $timer.customShortBreakMinutes,
                range: 1...60
            )
            stepperRow(
                title: l10n.t(.focus_custom_longBreak),
                value: $timer.customLongBreakMinutes,
                range: 5...90
            )

            Divider().padding(.vertical, 2)

            HStack {
                Text(l10n.t(.focus_dailyGoal))
                    .font(.system(size: 12))
                Spacer()
                Stepper("", value: $timer.dailyGoal, in: 1...20)
                    .labelsHidden()
                Text("\(timer.dailyGoal)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(minWidth: 20, alignment: .trailing)
            }

            HStack {
                Spacer()
                Button(l10n.t(.done)) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(width: 340)
    }

    private func stepperRow(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Stepper("", value: value, in: range)
                .labelsHidden()
            Text("\(value.wrappedValue)m")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(minWidth: 40, alignment: .trailing)
        }
    }
}
