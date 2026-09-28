/// Four-piece armor sets (hat, body, gloves, boots), like Flyff's. Pieces drop very rarely;
/// wearing more of one set unlocks bigger bonuses, and the full set is a big jump.
public enum ItemSet: String, Codable, Sendable, CaseIterable {
    /// Level 5, anyone. Each piece drops in a different zone.
    case dewleaf
    /// Level 15 class sets, dropped for the killer's class by the Hollow Owl (and, rarely, the fen and the outer ring).
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
    public var definition: SetDefinition {
        switch self {
        case .dewleaf:
            SetDefinition(
                id: self, name: "Dewleaf Set",
                pieces: [.dewleafCap, .dewleafVest, .dewleafGloves, .dewleafSlippers], playerClass: nil,
                tiers: [
                    .init(pieces: 2, bonus: StatBonus(maxHP: 20, maxMP: 10)),
                    .init(pieces: 3, bonus: StatBonus(attack: 3, defense: 3)),
                    .init(pieces: 4, bonus: StatBonus(attack: 6, maxHP: 50, attackSpeed: 0.15, critical: 0.05)),
                ])
        case .thistledown:
            SetDefinition(
                id: self, name: "Thistledown Set",
                pieces: [.thistledownCap, .thistledownCoat, .thistledownGloves, .thistledownBoots], playerClass: nil,
                tiers: [
                    .init(pieces: 2, bonus: StatBonus(maxHP: 60, maxMP: 30)),
                    .init(pieces: 3, bonus: StatBonus(attack: 8, defense: 8)),
                    .init(pieces: 4, bonus: StatBonus(attack: 14, maxHP: 150, attackSpeed: 0.12, critical: 0.06)),
                ])
        case .heartwood:
            SetDefinition(
                id: self, name: "Heartwood Set",
                pieces: [.heartwoodHelm, .heartwoodPlate, .heartwoodGauntlets, .heartwoodGreaves], playerClass: .guardian,
                tiers: [
                    .init(pieces: 2, bonus: StatBonus(maxHP: 60)),
                    .init(pieces: 3, bonus: StatBonus(defense: 8)),
                    .init(pieces: 4, bonus: StatBonus(attack: 8, defense: 12, maxHP: 200, attackSpeed: 0.1)),
                ])
        case .briar:
            SetDefinition(
                id: self, name: "Briar Set",
                pieces: [.briarHood, .briarJerkin, .briarBracers, .briarTreads], playerClass: .thornshot,
                tiers: [
                    .init(pieces: 2, bonus: StatBonus(attack: 6)),
                    .init(pieces: 3, bonus: StatBonus(critical: 0.08)),
                    .init(pieces: 4, bonus: StatBonus(attack: 10, maxHP: 60, attackSpeed: 0.2, critical: 0.07)),
                ])
        case .mycelium:
            SetDefinition(
                id: self, name: "Mycelium Set",
                pieces: [.myceliumCowl, .myceliumRobe, .myceliumGloves, .myceliumSlippers], playerClass: .sporecaster,
                tiers: [
                    .init(pieces: 2, bonus: StatBonus(maxMP: 60)),
                    .init(pieces: 3, bonus: StatBonus(attack: 8)),
                    .init(pieces: 4, bonus: StatBonus(attack: 18, maxHP: 50, maxMP: 100, critical: 0.08)),
                ])
        case .rainpetal:
            SetDefinition(
                id: self, name: "Rainpetal Set",
                pieces: [.rainpetalCirclet, .rainpetalGown, .rainpetalMitts, .rainpetalSandals], playerClass: .dewkeeper,
                tiers: [
                    .init(pieces: 2, bonus: StatBonus(maxHP: 40, maxMP: 40)),
                    .init(pieces: 3, bonus: StatBonus(defense: 6)),
                    .init(pieces: 4, bonus: StatBonus(defense: 6, maxHP: 120, maxMP: 80, attackSpeed: 0.15)),
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
