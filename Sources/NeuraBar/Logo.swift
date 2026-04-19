import SwiftUI
import AppKit

/// A proper NeuraBar mark — a rounded hexagon with a neural "N" of connected nodes.
/// Scales cleanly from 14pt menu bar up to 1024pt app icon.
struct NeuraMark: Shape {
    func path(in rect: CGRect) -> Path {
        // Rounded hexagon — 2026 vibe, distinct from typical rounded square icons.
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let cy = rect.midY
        let radius = min(w, h) * 0.5
        var path = Path()
        for i in 0..<6 {
            let angle = CGFloat.pi / 3 * CGFloat(i) - CGFloat.pi / 2
            let x = cx + radius * cos(angle)
            let y = cy + radius * sin(angle)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}

/// The colored in-app logo used in the About screen, settings, empty states.
/// Pass `animated: true` for a slow breathing / shimmer effect.
struct LogoView: View {
    var size: CGFloat = 56
    var showWordmark: Bool = false
    var animated: Bool = false

    @State private var breathe = false
    @State private var shimmerPhase: CGFloat = 0

    var body: some View {
        HStack(spacing: max(6, size * 0.18)) {
            mark
                .frame(width: size, height: size)
                .scaleEffect(animated && breathe ? 1.03 : 1.0)
                .animation(animated ? .easeInOut(duration: 2.4).repeatForever(autoreverses: true) : .default,
                           value: breathe)
                .onAppear { if animated { breathe = true } }
            if showWordmark {
                Text("NeuraBar")
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var mark: some View {
        ZStack {
            // Hexagon body with gradient + glossy highlight
            NeuraMark()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.58, green: 0.35, blue: 1.00),
                            Color(red: 0.30, green: 0.55, blue: 1.00),
                            Color(red: 0.22, green: 0.78, blue: 0.95)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            NeuraMark()
                .stroke(Color.white.opacity(0.25), lineWidth: size * 0.02)

            // Inner neural "N" — 4 nodes connected.
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height)
                let inset = s * 0.22
                let r = s / 2
                let cx = geo.size.width / 2
                let cy = geo.size.height / 2
                let p1 = CGPoint(x: cx - r + inset, y: cy + r - inset) // bottom-left
                let p2 = CGPoint(x: cx - r + inset, y: cy - r + inset) // top-left
                let p3 = CGPoint(x: cx + r - inset, y: cy + r - inset) // bottom-right
                let p4 = CGPoint(x: cx + r - inset, y: cy - r + inset) // top-right
                let dot = s * 0.10

                Path { p in
                    p.move(to: p1); p.addLine(to: p2)
                    p.addLine(to: p3); p.addLine(to: p4)
                }
                .stroke(Color.white.opacity(0.95),
                        style: StrokeStyle(lineWidth: s * 0.09, lineCap: .round, lineJoin: .round))

                let nodes = [p1, p2, p3, p4]
                ForEach(Array(nodes.enumerated()), id: \.offset) { _, pt in
                    Circle()
                        .fill(Color.white)
                        .frame(width: dot * 2, height: dot * 2)
                        .position(pt)
                }

                // Sparkle accent
                Image(systemName: "sparkle")
                    .font(.system(size: s * 0.14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .position(x: cx + r * 0.55, y: cy - r * 0.55)
            }
        }
        // Soft ambient shadow
        .shadow(color: Color.purple.opacity(0.35), radius: size * 0.08, y: size * 0.03)
    }
}

// MARK: - Menu bar icon (template, monochrome)

struct MenuBarIconView: View {
    /// Live system alert level drives the "critical" (red glyph) and "warning"
    /// (orange dot) persistent states.
    @EnvironmentObject var system: SystemMonitor
    /// Pomodoro owns an active-session indicator: while running, the menu
    /// bar glyph swaps to a phase-tinted timer.
    @EnvironmentObject var pomodoro: PomodoroTimer
    /// Short-lived events (copy / recording saved / automation done) flash
    /// a colored glyph over the icon for ~1.4 s before reverting.
    @ObservedObject var events = MenuBarStatusCoordinator.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            primaryGlyph
            // Warning-level badge: a small orange dot sits on top of whichever
            // base glyph is showing. Critical state replaces the glyph
            // entirely (see `primaryGlyph`), so this only fires for warnings.
            if system.alertLevel == .warning && events.currentEvent == nil {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .offset(x: 3, y: -2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 22, height: 22)
        .animation(.spring(duration: 0.28, bounce: 0.35), value: events.currentEvent)
        .animation(.easeInOut(duration: 0.2), value: system.alertLevel)
        .animation(.easeInOut(duration: 0.22), value: pomodoro.running)
        .animation(.easeInOut(duration: 0.22), value: pomodoro.phase)
    }

    /// What the main icon looks like at a given moment. Precedence, high→low:
    ///   1. A flashing event (copy / recording saved / automation done / failed)
    ///   2. The system is critical (pulsing red warning triangle)
    ///   3. Pomodoro is running (phase-tinted timer glyph with variable-color pulse)
    ///   4. The baseline template NeuraMark
    @ViewBuilder
    private var primaryGlyph: some View {
        if let event = events.currentEvent {
            Image(systemName: event.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(event.tint)
                .symbolEffect(.bounce, value: event)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        } else if system.alertLevel == .critical {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating)
                .transition(.scale.combined(with: .opacity))
        } else if pomodoro.running {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(phaseTint(for: pomodoro.phase))
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
        } else if let nsImage = Self.templateImage() {
            Image(nsImage: nsImage)
                .transition(.opacity)
        } else {
            Image(systemName: "sparkles")
        }
    }

    /// Matches the colors used by the Focus tab's timer dial gradient, so the
    /// two surfaces feel like the same thing.
    private func phaseTint(for phase: PomodoroTimer.Phase) -> Color {
        switch phase {
        case .focus, .idle: return .purple
        case .shortBreak:   return .green
        case .longBreak:    return .teal
        }
    }

    /// Render the neural-N glyph to a 20×20 monochrome NSImage flagged as template.
    @MainActor
    private static func templateImage() -> NSImage? {
        let size = CGSize(width: 20, height: 20)
        let renderer = ImageRenderer(content: MenuBarGlyph())
        renderer.scale = 2.0
        renderer.proposedSize = ProposedViewSize(size)
        guard let cg = renderer.cgImage else { return nil }
        let nsImg = NSImage(cgImage: cg, size: size)
        nsImg.isTemplate = true
        return nsImg
    }
}

// MARK: - Brand ambience

/// A subtle full-surface gradient wash used as the backdrop in the big window
/// mode. Evokes Liquid Glass without touching macOS-26-only APIs.
struct BrandWatermark: View {
    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color(red: 0.58, green: 0.35, blue: 1.00).opacity(0.18),
                    Color(red: 0.22, green: 0.55, blue: 1.00).opacity(0.08),
                    .clear
                ],
                center: UnitPoint(x: 0.15, y: 0.0),
                startRadius: 40, endRadius: 600
            )
            RadialGradient(
                colors: [
                    Color(red: 0.22, green: 0.78, blue: 0.95).opacity(0.14),
                    .clear
                ],
                center: UnitPoint(x: 0.95, y: 1.0),
                startRadius: 20, endRadius: 480
            )
        }
        .allowsHitTesting(false)
    }
}

/// One-time launch splash — a logo that animates in via a three-phase
/// choreography (drop in → settle → hold) using `phaseAnimator`.
struct BrandSplash: View {
    enum Phase: CaseIterable { case hidden, dropIn, settle }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                LogoView(size: 84, animated: true)
                    .phaseAnimator(Phase.allCases) { logo, phase in
                        logo
                            .scaleEffect(phase == .hidden ? 0.6 : (phase == .dropIn ? 1.08 : 1.0))
                            .opacity(phase == .hidden ? 0 : 1)
                            .rotationEffect(.degrees(phase == .hidden ? -8 : 0))
                    } animation: { phase in
                        switch phase {
                        case .hidden:  return .easeInOut(duration: 0)
                        case .dropIn:  return .spring(duration: 0.42, bounce: 0.45)
                        case .settle:  return .spring(duration: 0.35, bounce: 0.1)
                        }
                    }
                Text("NeuraBar")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .phaseAnimator(Phase.allCases) { txt, phase in
                        txt
                            .opacity(phase == .hidden ? 0 : 1)
                            .offset(y: phase == .hidden ? 8 : 0)
                    } animation: { _ in
                        .spring(duration: 0.5, bounce: 0.2)
                    }
            }
        }
    }
}

/// Small animated "AI is working" pulse — a sparkle that rotates / fades.
/// Drop next to streaming text for a live, on-brand heartbeat.
struct BrandPulse: View {
    var size: CGFloat = 14
    @State private var rotate = false
    @State private var glow = false

    var body: some View {
        ZStack {
            Circle()
                .fill(NB.brand)
                .frame(width: size, height: size)
                .opacity(glow ? 0.9 : 0.55)
                .scaleEffect(glow ? 1.15 : 1.0)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.55, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(rotate ? 360 : 0))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glow = true
            }
            withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                rotate = true
            }
        }
    }
}

/// 20×20 menu-bar glyph — stripped-down NeuraMark suitable for template rendering.
private struct MenuBarGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let inset = s * 0.22
            let r = s / 2
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let p1 = CGPoint(x: cx - r + inset, y: cy + r - inset)
            let p2 = CGPoint(x: cx - r + inset, y: cy - r + inset)
            let p3 = CGPoint(x: cx + r - inset, y: cy + r - inset)
            let p4 = CGPoint(x: cx + r - inset, y: cy - r + inset)
            let dot = s * 0.10

            ZStack {
                NeuraMark()
                    .stroke(Color.black, lineWidth: s * 0.08)

                Path { p in
                    p.move(to: p1); p.addLine(to: p2)
                    p.addLine(to: p3); p.addLine(to: p4)
                }
                .stroke(Color.black,
                        style: StrokeStyle(lineWidth: s * 0.1, lineCap: .round, lineJoin: .round))

                let nodes = [p1, p2, p3, p4]
                ForEach(Array(nodes.enumerated()), id: \.offset) { _, pt in
                    Circle().fill(Color.black).frame(width: dot * 1.8, height: dot * 1.8).position(pt)
                }
            }
        }
        .frame(width: 20, height: 20)
    }
}
