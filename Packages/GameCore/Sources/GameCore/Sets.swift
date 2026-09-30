/// Four-piece armor sets (hat, body, gloves, boots), like Flyff's. The class sets are sold at the armor
/// shop (saving up for your job's set is a Flyff rite of passage); Dewleaf and Thistledown only drop, and
/// very rarely. Wearing more of one set unlocks bigger bonuses, and the full set is a big jump.
public enum ItemSet: String, Codable, Sendable, CaseIterable {
    /// Level 5, anyone. Each piece drops in a different zone.
    case dewleaf
    /// Level 15 class sets: sold by Enoki, and dropped for the killer's class by bosses and Giants (and,
    /// very rarely, the outer ring).
    case heartwood, briar, mycelium, rainpetal
    /// Level 20, anyone. Each piece drops in a different zone of the outer ring.
    case thistledown
}

public struct SetDefinition: Sendable {
    public struct Tier: Sendable {
        /// Pieces worn to unlock it.
        public let pieces: Int
        public let bonus: StatBonus
    }

    public let id: ItemSet
    public let name: String
    /// Hat, body, gloves, boots.
    public let pieces: [ItemID]
    /// Only this class may wear it; nil = anyone.
    public let playerClass: PlayerClass?
    /// Cumulative: wearing 4 pieces grants the 2-, 3-, and 4-piece bonuses.
    public let tiers: [Tier]

    /// Everything the set grants when `worn` of its pieces are equipped.
    public func bonus(worn: Int) -> StatBonus {
        tiers.filter { $0.pieces <= worn }.reduce(StatBonus()) { $0 + $1.bonus }
    }
}

extension ItemSet {
    // As in Flyff, set effects are mostly stat points ("STA +3") that feed everything the stat does,
    // and the full set adds a burst of attack speed or HP on top.
    public var definition: SetDefinition {
        switch self {
        case .dewleaf:
            SetDefinition(
                id: self, name: "Dewleaf Set",
                pieces: [.dewleafCap, .dewleafVest, .dewleafGloves, .dewleafSlippers], playerClass: nil,
                tiers: [
                    .init(pieces: 2, bonus: StatBonus(maxHP: 20, stamina: 2)),
                    .init(pieces: 3, bonus: StatBonus(defense: 3, strength: 2)),
                    .init(pieces: 4, bonus: StatBonus(maxHP: 40, attackSpeed: 0.08, dexterity: 3)),
                ])
        case .thistledown:
            SetDefinition(
                id: self, name: "Thistledown Set",
                pieces: [.thistledownCap, .thistledownCoat, .thistledownGloves, .thistledownBoots], playerClass: nil,
                tiers: [
                    .init(pieces: 2, bonus: StatBonus(maxHP: 60, stamina: 3)),
                    .init(pieces: 3, bonus: StatBonus(defense: 8, strength: 3)),
                    .init(pieces: 4, bonus: StatBonus(maxHP: 120, attackSpeed: 0.1, critical: 0.04, dexterity: 4)),
                ])
        case .heartwood:
            SetDefinition(
                id: self, name: "Heartwood Set",
                pieces: [.heartwoodHelm, .heartwoodPlate, .heartwoodGauntlets, .heartwoodGreaves], playerClass: .guardian,
                tiers: [
                    .init(pieces: 2, bonus: StatBonus(stamina: 3)),
                    .init(pieces: 3, bonus: StatBonus(defense: 8, strength: 2)),
                    .init(pieces: 4, bonus: StatBonus(defense: 10, maxHP: 180, attackSpeed: 0.08, stamina: 4)),
                ])
        case .briar:
            SetDefinition(
                id: self, name: "Briar Set",
                pieces: [.briarHood, .briarJerkin, .briarBracers, .briarTreads], playerClass: .thornshot,
                tiers: [
                    .init(pieces: 2, bonus: StatBonus(dexterity: 3)),
                    .init(pieces: 3, bonus: StatBonus(critical: 0.05)),
                    .init(pieces: 4, bonus: StatBonus(maxHP: 60, attackSpeed: 0.12, dexterity: 5)),
                ])
        case .mycelium:
            SetDefinition(
                id: self, name: "Mycelium Set",
                pieces: [.myceliumCowl, .myceliumRobe, .myceliumGloves, .myceliumSlippers], playerClass: .sporecaster,
                tiers: [
                    .init(pieces: 2, bonus: StatBonus(intelligence: 3)),
                    .init(pieces: 3, bonus: StatBonus(maxMP: 60)),
                    .init(pieces: 4, bonus: StatBonus(maxHP: 60, critical: 0.05, intelligence: 6)),
                ])
        case .rainpetal:
            SetDefinition(
                id: self, name: "Rainpetal Set",
                pieces: [.rainpetalCirclet, .rainpetalGown, .rainpetalMitts, .rainpetalSandals], playerClass: .dewkeeper,
                tiers: [
                    .init(pieces: 2, bonus: StatBonus(stamina: 2, intelligence: 2)),
                    .init(pieces: 3, bonus: StatBonus(defense: 6)),
                    .init(pieces: 4, bonus: StatBonus(maxHP: 100, attackSpeed: 0.08, stamina: 3, intelligence: 4)),
                ])
        }
    }

    /// A class's own set.
    public static func forClass(_ playerClass: PlayerClass) -> ItemSet? {
        allCases.first { $0.definition.playerClass == playerClass }
    }

    /// How many pieces of this set `equipment` wears.
    public func worn(in equipment: [EquipSlot: Gear]) -> Int {
        let pieces = definition.pieces
        return equipment.values.count { pieces.contains($0.item) }
    }

    /// All set bonuses `equipment` has unlocked.
    public static func bonus(for equipment: [EquipSlot: Gear]) -> StatBonus {
        allCases.reduce(StatBonus()) { total, set in total + set.definition.bonus(worn: set.worn(in: equipment)) }
    }
}
