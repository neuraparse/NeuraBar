import SwiftUI

/// Design tokens for NeuraBar — 2026 / macOS Tahoe era.
/// Lightweight helpers here keep the look consistent across views.
enum NB {
    // MARK: Spacing
    static let sp1: CGFloat = 4
    static let sp2: CGFloat = 6
    static let sp3: CGFloat = 8
    static let sp4: CGFloat = 10
    static let sp5: CGFloat = 14
    static let sp6: CGFloat = 18
    static let sp7: CGFloat = 24

    // MARK: Radii
    static let rSm: CGFloat = 6
    static let rMd: CGFloat = 9
    static let rLg: CGFloat = 12
    static let rXl: CGFloat = 16

    // MARK: Panel dimensions
    static let panelWidth: CGFloat = 440
    static let panelHeight: CGFloat = 580

    // MARK: Brand gradient
    static let brand = LinearGradient(
        colors: [Color(red: 0.55, green: 0.35, blue: 0.98), Color(red: 0.34, green: 0.55, blue: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let accentPurple = Color(red: 0.49, green: 0.23, blue: 0.93)
}

// MARK: - Glass surface

/// Glass-style surface using layered SwiftUI Materials. We deliberately avoid
/// macOS 26's `.glassEffect()` modifier so the project compiles against any
/// modern macOS SDK (Xcode 16.3 ships SDK 15.4). The multi-layer approach
/// reproduces most of the Liquid Glass look: ultra-thin material, optional
/// tint, and a hairline edge.
struct GlassBackground: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    if let tint = tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.14))
                    }
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
            }
    }
}

extension View {
    func nbGlass(cornerRadius: CGFloat = NB.rLg, tint: Color? = nil) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, tint: tint))
    }
}

// MARK: - Card surface (for content — NOT glass)
// Per Apple HIG: glass is for navigation, not content.

struct CardBackground: ViewModifier {
    let cornerRadius: CGFloat
    let elevated: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(elevated ? 0.07 : 0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
            }
    }
}

extension View {
    func nbCard(cornerRadius: CGFloat = NB.rMd, elevated: Bool = false) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius, elevated: elevated))
    }
}

// MARK: - Animated pressable button

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Hover highlight for rows

struct HoverHighlight: ViewModifier {
    @State private var hover = false
    let cornerRadius: CGFloat
    let intensity: Double

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(hover ? intensity : 0))
            }
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.15), value: hover)
    }
}

extension View {
    func nbHoverHighlight(cornerRadius: CGFloat = NB.rSm, intensity: Double = 0.06) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, intensity: intensity))
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    let trailing: AnyView?

    init(_ title: String, trailing: AnyView? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)
            Spacer()
            if let trailing = trailing { trailing }
        }
        .padding(.bottom, 2)
    }
}
