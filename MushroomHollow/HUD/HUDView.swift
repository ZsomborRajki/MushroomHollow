import GameCore
import SwiftUI

/// Read-only heads-up display: player and target frames, quests, loot feed, XP, banners.
struct HUDView: View {
    let session: GameSession

    var body: some View {
        // The frames' glass is rendered together over the live 3D view (see ActionBar).
        GlassEffectContainer(spacing: 4) {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                if let player = session.hud.player {
                    VStack(alignment: .leading, spacing: 6) {
                        PlayerFrame(status: player, zone: session.zone, timeOfDay: session.timeOfDay)
                        // Under your own frame, clear of the buttons along the top.
                        // The boss bar already shows the boss; don't repeat it in the target frame.
                        if let target = session.hud.target, target.id != session.hud.boss?.id {
                            TargetFrame(target: target)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                        BuffRow(session: session, buffs: player.buffs)
                    }
                }
                Spacer()
                QuestTracker(quests: session.trackedQuests)
            }
            if let banner = session.banner {
                BannerView(banner: banner)
                    .padding(.top, 24)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Spacer()
            HStack(alignment: .bottom) {
                LootFeed(lines: session.feed)
                Spacer()
            }
            if let toast = session.toast {
                Text(toast)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(.red.opacity(0.25)), in: .capsule)
                    .transition(.opacity)
                    .padding(.bottom, 8)
            }
            // Bottom center keeps the (huge) boss itself in view.
            if let boss = session.hud.boss {
                BossBar(boss: boss)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let player = session.hud.player {
                XPBar(status: player)
            }
            #if DEBUG
            Text(session.debugText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 44) // clear of the mute button
            #endif
        }
        }
        .padding()
        .animation(.snappy, value: session.hud.target?.id)
        .animation(.snappy, value: session.hud.boss?.id)
        .animation(.bouncy, value: session.banner)
        .animation(.easeOut(duration: 0.2), value: session.toast)
        .animation(.snappy, value: session.feed)
        .allowsHitTesting(false)
    }
}

// MARK: - Frames

private struct PlayerFrame: View {
    let status: PlayerStatus
    let zone: Zone?
    let timeOfDay: Float

    private var clock: (symbol: String, label: String) {
        switch timeOfDay {
        case 0.22..<0.3: ("sunrise.fill", "Dawn")
        case 0.3..<0.7: ("sun.max.fill", "Day")
        case 0.7..<0.8: ("sunset.fill", "Dusk")
        default: ("moon.stars.fill", "Night")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text("Sprout")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                Text("Lv \(status.stats.level)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.white.opacity(0.18), in: .capsule)
                if let playerClass = status.playerClass {
                    Image(systemName: playerClass.symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(playerClass.tint)
                        .accessibilityLabel(playerClass.definition.name)
                }
                Spacer(minLength: 0)
                Label("\(status.caps)", systemImage: "circle.circle.fill")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .labelStyle(TightLabelStyle())
                    .foregroundStyle(.yellow)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize()
            }
            StatBar(value: status.stats.hp, max: status.stats.maxHP, color: .red, label: "HP", height: 11)
            StatBar(value: status.stats.mp, max: status.stats.maxMP, color: .blue, label: "MP", height: 11)
            if status.pet.isSummoned || status.pet.awaitingFood, let name = status.pet.slot?.definition.name {
                PetBar(pet: status.pet, name: name)
            }
            if let zone {
                HStack(spacing: 4) {
                    Image(systemName: status.isSlowed ? "tortoise.fill" : "location.fill")
                    Text(zone.name)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let levels = zone.levels {
                        Text("\(levels.lowerBound)–\(levels.upperBound)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                    if status.isFlying {
                        Label("\(Int(status.altitude)) m", systemImage: "wind")
                            .labelStyle(TightLabelStyle())
                            .foregroundStyle(.cyan)
                            .fixedSize()
                    } else {
                        Image(systemName: clock.symbol)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(clock.label)
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(status.isSlowed ? .yellow : .primary)
            }
        }
        .frame(width: 170)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .animation(.snappy, value: status.caps)
    }
}

/// Icon and title with less of a gap than the default label style.
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
            configuration.title
        }
    }
}

/// Your pet's belly: a slim bar that turns red (and says so) when it's hungry.
private struct PetBar: View {
    let pet: PetStatus
    let name: String

    private var color: Color {
        pet.awaitingFood || pet.isHungry ? .red : pet.fullness < 0.5 ? .orange : .green
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: pet.awaitingFood ? "house.fill" : "pawprint.fill")
                .foregroundStyle(color)
            Text(name).font(.caption2.weight(.bold))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.4))
                    Capsule().fill(color.gradient).frame(width: geometry.size.width * CGFloat(pet.fullness))
                }
            }
            .frame(height: 6)
            Text(pet.awaitingFood ? "Starving" : pet.isHungry ? "Hungry" : "\(pet.minutesLeft) min")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(pet.isHungry || pet.awaitingFood ? .red : .secondary)
                .fixedSize()
        }
        .font(.caption2)
    }
}

/// The world boss's health, with markers where its fight changes phase.
private struct BossBar: View {
    let boss: BossInfo

    private var fraction: Double { boss.maxHP > 0 ? Double(boss.hp) / Double(boss.maxHP) : 0 }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                if let element = boss.element {
                    ElementBadge(element: element, size: 20)
                } else {
                    Image(systemName: "moon.stars.fill").foregroundStyle(.indigo)
                }
                Text(boss.name).font(.headline)
                if boss.isFighting {
                    Image(systemName: "flame.fill").foregroundStyle(.red).font(.caption)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.45))
                    Capsule()
                        .fill(.linearGradient(colors: [.purple, .red], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * fraction)
                    // Phase thresholds: wing gusts below 60%, summons and enrage below 30%.
                    ForEach([0.6, 0.3], id: \.self) { mark in
                        Rectangle()
                            .fill(.white.opacity(0.7))
                            .frame(width: 2)
                            .offset(x: geometry.size.width * mark)
                    }
                    Text("\(boss.hp) / \(boss.maxHP)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .shadow(radius: 1)
                }
            }
            .frame(width: 280, height: 14)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(.purple.opacity(0.2)), in: .rect(cornerRadius: 16))
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

/// Active buffs with a draining ring.
private struct BuffRow: View {
    let session: GameSession
    /// Which buffs are up; their timers come from `session.timers`.
    let buffs: [BuffStatus]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(buffs) { buff in
                ZStack {
                    Circle().fill(.black.opacity(0.35))
                    BuffRing(session: session, skill: buff.skill)
                    Image(systemName: buff.skill.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(buff.skill.tint)
                }
                .frame(width: 30, height: 30)
            }
        }
        .animation(.snappy, value: buffs.map(\.id))
    }
}

/// The draining ring; the only part of the buff row that watches the ticking timers.
private struct BuffRing: View {
    let session: GameSession
    let skill: SkillID

    var body: some View {
        let countdown = session.timers.buffs[skill] ?? .init()
        Circle()
            .trim(from: 0, to: countdown.fraction)
            .stroke(skill.tint, lineWidth: 2.5)
            .rotationEffect(.degrees(-90))
            .accessibilityLabel("\(skill.definition.name), \(Int(countdown.remaining)) seconds")
    }
}

private struct TargetFrame: View {
    let target: TargetInfo

    /// Classic MMO con colors, the same as the nameplates: grey is trivial, red is dangerous.
    private var levelColor: Color {
        Color(uiColor: Nameplate.Tier(mobLevel: target.levelDelta, viewerLevel: 0).color)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if target.isFightingYou {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                } else if target.isAggressive {
                    // Attacks on sight; most mobs wait to be hit.
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .accessibilityLabel("Aggressive")
                }
                if let element = target.element {
                    // Flyff's element tile, so you know which stone it drops and what to hit it with.
                    ElementBadge(element: element, size: 18)
                }
                Text(target.name)
                    .font(.headline)
                Text("Lv \(target.level)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(levelColor)
            }
            StatBar(value: target.hp, max: target.maxHP, color: .red, label: nil)
            if let element = target.element {
                // What your weapon's element does against it (or, bare, what would work).
                HStack(spacing: 4) {
                    if let hint = target.matchup?.hint {
                        Image(systemName: hint.symbol)
                        Text("\(hint.text) · your weapon")
                    } else {
                        Text("Weak to")
                        ElementBadge(element: element.weakAgainst, size: 12)
                        Text(element.weakAgainst.displayName)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(target.matchup?.hint?.color ?? .secondary)
            }
        }
        .frame(width: 200)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

private struct QuestTracker: View {
    let quests: [(quest: QuestDefinition, text: String, ready: Bool)]

    var body: some View {
        if !quests.isEmpty {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(quests, id: \.quest.id) { entry in
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(entry.quest.title)
                            .font(.caption.weight(.bold))
                        Label(entry.text, systemImage: entry.ready ? "checkmark.seal.fill" : "scope")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(entry.ready ? .green : .secondary)
                    }
                }
            }
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .padding(.top, 64) // below the utility buttons
        }
    }
}

private struct LootFeed: View {
    let lines: [FeedLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines) { line in
                Label(line.text, systemImage: line.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(line.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(.leading, 190) // clear of the joystick
        .padding(.bottom, 6)
    }
}

private struct BannerView: View {
    let banner: Banner

    var body: some View {
        VStack(spacing: 2) {
            Text(banner.title)
                .font(.system(.title, design: .rounded, weight: .heavy))
                .foregroundStyle(.linearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
            Text(banner.subtitle)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(.yellow.opacity(0.2)), in: .capsule)
    }
}

private struct XPBar: View {
    let status: PlayerStatus

    private var fraction: Double {
        guard status.xpToNextLevel > 0 else { return 1 }
        return min(1, Double(status.xp) / Double(status.xpToNextLevel))
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("XP")
                .font(.caption2.weight(.bold))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.35))
                    Capsule()
                        .fill(.linearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 6)
            Text(fraction, format: .percent.precision(.fractionLength(1)))
                .font(.caption2.monospacedDigit())
        }
        .frame(maxWidth: 340)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

struct StatBar: View {
    let value: Int
    let max: Int
    let color: Color
    let label: String?
    var height: CGFloat = 16

    private var fraction: Double { max > 0 ? Double(value) / Double(max) : 0 }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.4))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: geometry.size.width * fraction)
                HStack {
                    if let label { Text(label).fontWeight(.bold) }
                    Spacer()
                    Text("\(value) / \(max)").monospacedDigit()
                }
                // Thin bars get smaller numbers so they still fit inside.
                .font(height < 14 ? .system(size: 9, weight: .medium) : .caption2)
                .padding(.horizontal, height < 14 ? 6 : 8)
                .shadow(radius: 1)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.25), value: fraction)
    }
}
