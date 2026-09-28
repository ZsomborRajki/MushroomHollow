import GameCore
import SwiftUI

/// Bottom-right combat cluster: a big attack button with skills arced around it.
/// Works with touch; shows the matching controller button when a pad is connected.
struct ActionBar: View {
    let session: GameSession

    /// Layout inside a fixed box, attack button in the bottom-right corner.
    private static let size = CGSize(width: 330, height: 280)
    private static let attackCenter = CGPoint(x: 270, y: 220)

    /// Base skills on an inner arc, class skills on an outer arc between them.
    private static func skillPosition(_ index: Int) -> CGPoint {
        let (radius, degrees): (CGFloat, Double) = index < 3 ? (100, 180 + Double(index) * 45) : (172, 200 + Double(index - 3) * 50)
        let angle = Angle.degrees(degrees).radians
        return CGPoint(x: attackCenter.x + cos(angle) * radius, y: attackCenter.y + sin(angle) * radius)
    }

    var body: some View {
        let player = session.hud.player
        let glyphs = session.glyphs

        ZStack {
            if player?.isFlying == true {
                ClimbButton(symbol: "arrow.up", glyph: glyphs.map { _ in "rt.rectangle.roundedtop" }) { session.setTouchClimb($0 ? 1 : 0) }
                    .position(x: Self.attackCenter.x, y: Self.attackCenter.y - 95)
                ClimbButton(symbol: "arrow.down", glyph: glyphs.map { _ in "lt.rectangle.roundedtop" }) { session.setTouchClimb($0 ? -1 : 0) }
                    .position(Self.attackCenter)
            } else {
                ForEach(Array((player?.skills ?? []).enumerated()), id: \.element.id) { index, status in
                    SkillButton(session: session, skill: status.id, status: status, glyph: glyphs.map { $0.skills[min(index, $0.skills.count - 1)] },
                                shiftGlyph: index >= 3 ? glyphs?.shift : nil) {
                        session.perform(.skill(index))
                    }
                    .position(Self.skillPosition(index))
                }

                RoundButton(symbol: "scope", size: 44, glyph: glyphs?.nextTarget) {
                    session.perform(.cycleTarget(1))
                }
                .accessibilityLabel("Next target")
                .position(x: 135, y: 52)

                RoundButton(symbol: "figure.fencing", size: 88, tint: .red, glyph: glyphs?.primary) {
                    session.perform(.primary)
                }
                .accessibilityLabel("Attack")
                .position(Self.attackCenter)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .padding(.trailing, 30)
        .padding(.bottom, 22)
        .animation(.snappy, value: player?.isFlying)
    }
}

/// Hold to climb or descend while flying.
private struct ClimbButton: View {
    let symbol: String
    let glyph: String?
    let onHold: (Bool) -> Void
    @State private var isHeld = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 28, weight: .bold))
            .frame(width: 72, height: 72)
            .glassEffect(.regular.tint(.cyan.opacity(isHeld ? 0.45 : 0.15)).interactive(), in: .circle)
            .overlay(alignment: .topTrailing) { GlyphBadge(symbol: glyph) }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isHeld { isHeld = true; onHold(true) }
                    }
                    .onEnded { _ in
                        isHeld = false
                        onHold(false)
                    }
            )
    }
}

private struct SkillButton: View {
    let session: GameSession
    let skill: SkillID
    /// Unlock and mana state only; the cooldown comes from `session.timers`.
    let status: SkillStatus?
    let glyph: String?
    var shiftGlyph: String?
    let action: () -> Void

    var body: some View {
        let unlocked = status?.isUnlocked ?? false
        let affordable = status?.canAfford ?? false

        Button(action: action) {
            ZStack {
                Image(systemName: unlocked ? skill.symbol : "lock.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(unlocked ? skill.tint : .secondary)

                CooldownSweep(session: session, skill: skill)
                if !unlocked {
                    Text("Lv \(skill.definition.requiredLevel)")
                        .font(.caption2.weight(.bold))
                        .offset(y: 20)
                }
            }
            .frame(width: 60, height: 60)
            .opacity(unlocked && !affordable ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 0) {
                if let shiftGlyph { GlyphBadge(symbol: shiftGlyph) }
                GlyphBadge(symbol: glyph)
            }
        }
        .overlay(alignment: .bottom) {
            if unlocked {
                Text("\(skill.definition.manaCost)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(.cyan)
                    .offset(y: 6)
            }
        }
        .accessibilityLabel(skill.definition.name)
    }
}

/// Cooldown sweep, like a clock hand wiping away. The only part of a skill button that
/// watches the ticking timers, so a cooldown doesn't redraw the whole action bar.
private struct CooldownSweep: View {
    let session: GameSession
    let skill: SkillID

    var body: some View {
        if let countdown = session.timers.skills[skill], countdown.remaining > 0 {
            Circle()
                .trim(from: 0, to: countdown.fraction)
                .rotation(.degrees(-90))
                .scale(x: -1)
                .fill(.black.opacity(0.55))
            Text("\(Int(ceil(countdown.remaining)))")
                .font(.headline.monospacedDigit())
        }
    }
}

struct PotionButton: View {
    let item: ItemID
    let count: Int
    let isCoolingDown: Bool
    let glyph: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: item.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(item.tint)
                if isCoolingDown {
                    Circle().fill(.black.opacity(0.45))
                }
            }
            .frame(width: 48, height: 48)
            .opacity(count > 0 ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .overlay(alignment: .bottomTrailing) {
            Text("\(count)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .padding(3)
                .background(.black.opacity(0.5), in: .capsule)
                .offset(x: 4, y: 4)
        }
        .overlay(alignment: .topLeading) {
            if let glyph {
                Image(systemName: glyph)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .offset(x: -4, y: -4)
            }
        }
        .accessibilityLabel(item.definition.name)
    }
}

struct RoundButton: View {
    let symbol: String
    let size: CGFloat
    var tint: Color = .white
    let glyph: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .overlay(alignment: .topTrailing) { GlyphBadge(symbol: glyph) }
    }
}

private struct GlyphBadge: View {
    let symbol: String?

    var body: some View {
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white, .black.opacity(0.6))
                .offset(x: 4, y: -4)
        }
    }
}

/// Shown after fainting.
struct FaintedOverlay: View {
    let glyph: String?
    let onRespawn: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("You fainted")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("The snails will tell stories about this.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: onRespawn) {
                Label("Wake up in Capstone", systemImage: glyph ?? "house.fill")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.green.opacity(0.3)).interactive(), in: .capsule)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.45))
    }
}

/// Damage numbers and XP popping out of the world. Redraws every frame while any are alive,
/// so it's one `Canvas` (no per-label views) with a single shadow pass over all of them.
struct FloatingTextLayer: View {
    let session: GameSession

    var body: some View {
        let texts = session.floatingTexts
        Canvas { context, _ in
            context.addFilter(.shadow(color: .black.opacity(0.7), radius: 2, y: 1))
            context.drawLayer { layer in
                for text in texts {
                    guard let point = text.screenPosition else { continue }
                    var label = layer
                    let scale = scale(for: text)
                    label.opacity = 1 - pow(text.progress, 3)
                    label.translateBy(x: point.x, y: point.y - text.progress * 50)
                    label.scaleBy(x: scale, y: scale)
                    label.draw(Text(text.text).font(font(for: text.style)).foregroundStyle(color(for: text.style)), at: .zero)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func font(for style: FloatingText.Style) -> Font {
        switch style {
        case .critical: .system(size: 30, weight: .black, design: .rounded)
        case .xp, .info: .system(size: 16, weight: .bold, design: .rounded)
        default: .system(size: 22, weight: .heavy, design: .rounded)
        }
    }

    private func color(for style: FloatingText.Style) -> Color {
        switch style {
        case .dealt: .white
        case .critical: .yellow
        case .taken: Color(red: 1, green: 0.35, blue: 0.3)
        case .heal: .green
        case .mana: .cyan
        case .xp: Color(red: 0.75, green: 0.6, blue: 1)
        case .info: .white
        }
    }

    /// A quick pop on spawn.
    private func scale(for text: FloatingText) -> Double {
        text.progress < 0.12 ? 0.6 + text.progress / 0.12 * 0.6 : 1.2 - min(0.2, (text.progress - 0.12) * 0.5)
    }
}
