/// Flyff's five elements. Every critter under the tree belongs to one, and weapons and body armor can be
/// infused with one at the blacksmith (+1 to +10) using the element's stone, which only that element's
/// critters drop.
///
/// The wheel runs fire → wind → earth → electric → water → fire: each element overpowers the next one
/// round. So a water blade cuts deep into fire critters, and water-infused armor shrugs off their bites,
/// while an electric critter hits water armor hard and shrugs off a water blade.
public enum Element: String, Codable, Sendable, CaseIterable {
    case fire, wind, earth, electric, water

    public var displayName: String {
        switch self {
        case .fire: "Fire"
        case .wind: "Wind"
        case .earth: "Earth"
        case .electric: "Electric"
        case .water: "Water"
        }
    }

    /// The element this one overpowers (the next one round the wheel).
    public var strongAgainst: Element {
        switch self {
        case .fire: .wind
        case .wind: .earth
        case .earth: .electric
        case .electric: .water
        case .water: .fire
        }
    }

    /// The element that overpowers this one.
    public var weakAgainst: Element {
        Element.allCases.first { $0.strongAgainst == self }!
    }

    /// The stone that infuses gear with this element.
    public var stone: ItemID {
        switch self {
        case .fire: .fireStone
        case .wind: .windStone
        case .earth: .earthStone
        case .electric: .electricStone
        case .water: .waterStone
        }
    }

    /// The element a stone infuses, if `item` is one.
    public init?(stone item: ItemID) {
        guard let element = Element.allCases.first(where: { $0.stone == item }) else { return nil }
        self = element
    }
}

/// How one element fares against another.
public enum ElementMatchup: Sendable, Equatable {
    /// The first overpowers the second.
    case strong
    /// The second overpowers the first.
    case weak
    case same
    case neutral

    public init(_ element: Element, against other: Element) {
        if element.strongAgainst == other { self = .strong }
        else if other.strongAgainst == element { self = .weak }
        else if element == other { self = .same }
        else { self = .neutral }
    }
}

/// An element infused into one piece of gear, +1...+10.
public struct ElementUpgrade: Codable, Sendable, Hashable {
    public var element: Element
    public var level: Int

    public init(_ element: Element, level: Int) {
        self.element = element
        self.level = level
    }
}

extension EquipSlot {
    /// Weapons (for attack) and body armor (for defense) take an element; nothing else does.
    public var takesElement: Bool { self == .weapon || self == .body }
}

extension ItemDefinition {
    public var takesElement: Bool { equipSlot?.takesElement ?? false }
}

extension MobKind {
    /// Each species' element, from what it is: damp things are water, buzzing and crackling things
    /// electric, fliers and drifters wind, diggers and armored things earth, hot-headed things fire.
    /// Summons share their parent's element. The fields walked in level order cycle through all five,
    /// so a sprout meets every element before level 10.
    public var element: Element {
        switch self {
        case .snail, .slug, .bogFrog, .mossTurtle, .thornrose: .water
        case .ladybug, .acornling, .emberNewt, .coneKnight: .fire
        case .aphid, .sporeBeast, .sporeling, .puffweed, .puffling, .duskMoth, .mantis, .owl: .wind
        case .pillBug, .earthworm, .weaverSpider, .hedgehog, .mouse, .delverMole, .moldywarp: .earth
        case .beetle, .cricket, .fuzzbee, .grumblecap, .stagBeetle, .rootcrawler: .electric
        }
    }
}

/// Tuning for element upgrades, done at the blacksmith like ordinary ones. Unlike ordinary upgrades a
/// failure never shatters the item: from +4 on it costs one element level instead (a Ward Charm keeps it).
/// Gear with an element only takes more of the same stone; the blacksmith can strip the element off
/// cheaply, or (for a small fortune in caps and Ward Charms) convert it to another element, level and all.
public enum ElementForge {
    public static let maxLevel = 10
    /// From this level on a weapon shows its element (drips, flames, sparks...), stronger every level.
    public static let visibleLevel = 3

    /// Chance that an attempt to reach `level` succeeds.
    public static func chance(toReach level: Int) -> Float {
        let table: [Float] = [1, 1, 0.9, 0.75, 0.6, 0.45, 0.3, 0.2, 0.12, 0.06]
        return table[max(1, min(level, maxLevel)) - 1]
    }

    public static func risk(toReach level: Int) -> Upgrade.Risk {
        level <= 3 ? .none : .downgrade
    }

    /// Element stones per attempt: one up to +3, then more the higher you go.
    public static func stoneCost(toReach level: Int) -> Int {
        switch level {
        case ...3: 1
        case ...6: 2
        case ...9: 3
        default: 5
        }
    }

    /// Caps per attempt.
    public static func capsCost(of item: ItemID, toReach level: Int) -> Int {
        (item.definition.requiredLevel + 4) * level * 5
    }

    /// Caps to strip an element off (the stones are lost).
    public static func removalCost(of item: ItemID) -> Int {
        (item.definition.requiredLevel + 4) * 5
    }

    /// Converting keeps the level but changes the element: a lot of Ward Charms and caps.
    public static func conversionCharms(level: Int) -> Int {
        max(2, level)
    }

    public static func conversionCaps(of item: ItemID, level: Int) -> Int {
        (item.definition.requiredLevel + 4) * max(1, level) * 40
    }

    /// Damage multiplier for an attack with a `weapon` element against a target of element `target`.
    /// Strong: +20%, plus 3% a level (+50% at +10). Weak: -20%. Same element: -10%. Otherwise 1% a level.
    public static func attackMultiplier(_ weapon: ElementUpgrade?, against target: Element?) -> Float {
        guard let weapon, weapon.level > 0 else { return 1 }
        guard let target else { return 1 + 0.01 * Float(weapon.level) }
        let level = Float(min(weapon.level, maxLevel))
        switch ElementMatchup(weapon.element, against: target) {
        case .strong: return 1.2 + 0.03 * level
        case .weak: return 0.8
        case .same: return 0.9
        case .neutral: return 1 + 0.01 * level
        }
    }

    /// Damage multiplier for an attack of element `attacker` against `armor`. Armor strong against the
    /// attacker's element takes 15% less, plus 2.5% a level (40% less at +10); armor the attacker's
    /// element overpowers takes 20% more.
    public static func defenseMultiplier(_ armor: ElementUpgrade?, against attacker: Element?) -> Float {
        guard let armor, armor.level > 0, let attacker else { return 1 }
        let level = Float(min(armor.level, maxLevel))
        switch ElementMatchup(armor.element, against: attacker) {
        case .strong: return 0.85 - 0.025 * level
        case .weak: return 1.2
        case .same: return 0.9
        case .neutral: return 1 - 0.01 * level
        }
    }

    /// How strongly a weapon shows its element: 0 below +3, then rising to 1 at +10.
    public static func effectStrength(level: Int) -> Float {
        guard level >= visibleLevel else { return 0 }
        return Float(min(level, maxLevel) - visibleLevel + 1) / Float(maxLevel - visibleLevel + 1)
    }
}

/// What happened at the element forge.
public enum ElementForgeResult: Codable, Sendable, Equatable {
    case succeeded(ElementUpgrade)
    /// Nothing lost but the materials.
    case failed(ElementUpgrade)
    /// Failed, but the Ward Charm kept the element as it was.
    case protected(ElementUpgrade)
    /// Failed and lost a level.
    case downgraded(ElementUpgrade)
    case removed
    case converted(ElementUpgrade)
}

extension GameSimulation {
    private func isAtForge(_ player: WorldEntity) -> Bool {
        NPCID.allCases.contains { $0.definition.upgradesGear && isNear($0, player) }
    }

    /// Raises a weapon's or body armor's element by one (see `ElementForge`).
    mutating func infuseElement(_ location: GearLocation, element: Element, protect: Bool,
                                player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player, player.stats.isAlive else { return .notAvailable }
        guard isAtForge(player) else { return .tooFar }
        guard let gear = Self.gear(at: location, in: data) else { return .missingItem }
        guard gear.definition.takesElement else { return .notUsable }
        if let current = gear.element, current.element != element { return .elementMismatch }
        let current = gear.element?.level ?? 0
        let target = current + 1
        guard target <= ElementForge.maxLevel else { return .maxUpgrade }

        let stones = ElementForge.stoneCost(toReach: target)
        let caps = ElementForge.capsCost(of: gear.item, toReach: target)
        let useCharm = protect && ElementForge.risk(toReach: target) != .none
        guard data.inventory.count(of: element.stone) >= stones else { return .missingMaterials }
        if useCharm, data.inventory.count(of: .wardCharm) == 0 { return .missingMaterials }
        guard data.caps >= caps else { return .notEnoughCaps }

        data.inventory.remove(element.stone, count: stones)
        if useCharm { data.inventory.remove(.wardCharm, count: 1) }
        data.caps -= caps
        events.append(.capsChanged(player: player.id, delta: -caps))

        let kept = ElementUpgrade(element, level: current)
        let result: ElementForgeResult
        if random.unit() < ElementForge.chance(toReach: target) {
            result = .succeeded(ElementUpgrade(element, level: target))
        } else if useCharm {
            result = .protected(kept)
        } else if ElementForge.risk(toReach: target) == .downgrade {
            result = .downgraded(ElementUpgrade(element, level: current - 1))
        } else {
            result = .failed(kept)
        }
        let upgrade: ElementUpgrade? = switch result {
        case let .succeeded(upgrade), let .failed(upgrade), let .protected(upgrade), let .downgraded(upgrade), let .converted(upgrade):
            upgrade.level > 0 ? upgrade : nil
        case .removed: nil
        }
        finishForging(gear, at: location, element: upgrade, result: result, data: &data, player: &player)
        return nil
    }

    /// Strips the element off for a few caps; the stones that went in are lost.
    mutating func removeElement(_ location: GearLocation, player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player, player.stats.isAlive else { return .notAvailable }
        guard isAtForge(player) else { return .tooFar }
        guard let gear = Self.gear(at: location, in: data) else { return .missingItem }
        guard gear.element != nil else { return .noElement }
        let caps = ElementForge.removalCost(of: gear.item)
        guard data.caps >= caps else { return .notEnoughCaps }
        data.caps -= caps
        events.append(.capsChanged(player: player.id, delta: -caps))
        finishForging(gear, at: location, element: nil, result: .removed, data: &data, player: &player)
        return nil
    }

    /// Turns the element into another at the same level, for Ward Charms and a pile of caps. Always works.
    mutating func convertElement(_ location: GearLocation, to element: Element, player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player, player.stats.isAlive else { return .notAvailable }
        guard isAtForge(player) else { return .tooFar }
        guard let gear = Self.gear(at: location, in: data) else { return .missingItem }
        guard let current = gear.element else { return .noElement }
        guard current.element != element else { return .notAvailable }
        let charms = ElementForge.conversionCharms(level: current.level)
        let caps = ElementForge.conversionCaps(of: gear.item, level: current.level)
        guard data.inventory.count(of: .wardCharm) >= charms else { return .missingMaterials }
        guard data.caps >= caps else { return .notEnoughCaps }
        data.inventory.remove(.wardCharm, count: charms)
        data.caps -= caps
        events.append(.capsChanged(player: player.id, delta: -caps))
        let converted = ElementUpgrade(element, level: current.level)
        finishForging(gear, at: location, element: converted, result: .converted(converted), data: &data, player: &player)
        return nil
    }

    private mutating func finishForging(_ gear: Gear, at location: GearLocation, element: ElementUpgrade?,
                                        result: ElementForgeResult, data: inout PlayerData, player: inout WorldEntity) {
        replace(gear, at: location, with: Gear(gear.item, upgrade: gear.upgrade, element: element), in: &data)
        player.player = data
        if case .equipped = location {
            refreshStats(&player)
            events.append(.equipmentChanged(player: player.id))
        }
        events.append(.elementForged(player: player.id, item: gear.item, result: result))
        reportCollectProgress(for: &player)
    }

    /// Damage multiplier from elements for `attacker` hitting `target`: a player's weapon element against
    /// a mob's element, or a mob's element against a player's body armor.
    static func elementMultiplier(attacker: WorldEntity, target: WorldEntity) -> Float {
        switch (attacker.kind, target.kind) {
        case let (.player, .mob(kind)):
            ElementForge.attackMultiplier(attacker.player?.equipment[.weapon]?.element, against: kind.element)
        case let (.mob(kind), .player):
            ElementForge.defenseMultiplier(target.player?.equipment[.body]?.element, against: kind.element)
        default:
            1
        }
    }
}
