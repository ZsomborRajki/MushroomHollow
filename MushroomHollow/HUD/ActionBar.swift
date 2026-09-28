import GameCore
import SwiftUI

/// Bottom-right combat cluster: a big attack button with skills arced around it.
/// Works with touch; shows the matching controller button when a pad is connected.
struct ActionBar: View {
    let session: GameSession

    /// Layout inside a fixed box, attack button in the bottom-right corner.
    private static let size = CGSize(width: 300, height: 250)
    private static let attackCenter = CGPoint(x: 240, y: 190)
    private static let skillRadius: CGFloat = 106

    var body: some View {
        let skills = session.hud.player?.skills ?? []
        let glyphs = session.glyphs

        ZStack {
            // Skills sit on an arc to the left of and above the attack button.
            ForEach(Array(SkillID.barOrder.enumerated()), id: \.element) { index, skill in
                let angle = Angle.degrees(180 + Double(index) * 45)
                SkillButton(skill: skill, status: skills.first { $0.id == skill }, glyph: glyphs?.skills[index]) {
                    session.perform(.skill(index))
                }
                .position(
                    x: Self.attackCenter.x + cos(angle.radians) * Self.skillRadius,
                    y: Self.attackCenter.y + sin(angle.radians) * Self.skillRadius)
            }

            RoundButton(symbol: "scope", size: 44, glyph: glyphs?.nextTarget) {
                session.perform(.cycleTarget(1))
            }
            .accessibilityLabel("Next target")
            .position(x: 102, y: 72)

            ForEach(Array([ItemID.dewPotion, .nectarVial].enumerated()), id: \.element) { index, item in
                PotionButton(item: item, count: session.hud.player?.inventory.count(of: item) ?? 0,
                             cooldown: session.hud.player?.itemCooldown ?? 0, glyph: glyphs?.quickItems[index]) {
                    session.perform(.quickItem(index))
                }
                // Up beside the skill arc, clear of the XP bar.
                .position(x: index == 0 ? 58 : 32, y: index == 0 ? 150 : 88)
            }

            RoundButton(symbol: "figure.fencing", size: 88, tint: .red, glyph: glyphs?.primary) {
                session.perform(.primary)
            }
            .accessibilityLabel("Attack")
            .position(Self.attackCenter)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .padding(.trailing, 30)
        .padding(.bottom, 22)
    }
}

private struct SkillButton: View {
    let skill: SkillID
    let status: SkillStatus?
    let glyph: String?
    let action: () -> Void

    private var cooldownFraction: Double {
        guard let status, status.cooldownTotal > 0 else { return 0 }
        return Double(status.cooldownRemaining / status.cooldownTotal)
    }

    var body: some View {
        let unlocked = status?.isUnlocked ?? false
        let affordable = status?.canAfford ?? false

        Button(action: action) {
            ZStack {
                Image(systemName: unlocked ? skill.symbol : "lock.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(unlocked ? skill.tint : .secondary)

                // Cooldown sweep, like a clock hand wiping away.
                if cooldownFraction > 0 {
                    Circle()
                        .trim(from: 0, to: cooldownFraction)
                        .rotation(.degrees(-90))
                        .scale(x: -1)
                        .fill(.black.opacity(0.55))
                    Text("\(Int(ceil(status?.cooldownRemaining ?? 0)))")
                        .font(.headline.monospacedDigit())
                }
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
        .overlay(alignment: .topTrailing) { GlyphBadge(symbol: glyph) }
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

private struct PotionButton: View {
    let item: ItemID
    let count: Int
    let cooldown: Float
    let glyph: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: item.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(item.tint)
                if cooldown > 0 {
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

/// Damage numbers and XP popping out of the world.
struct FloatingTextLayer: View {
    let texts: [FloatingText]

    var body: some View {
        ZStack {
            ForEach(texts) { text in
                if let point = text.screenPosition {
                    Text(text.text)
                        .font(font(for: text.style))
                        .foregroundStyle(color(for: text.style))
                        .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                        .scaleEffect(scale(for: text))
                        .opacity(1 - pow(text.progress, 3))
                        .position(x: point.x, y: point.y - text.progress * 50)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
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
