/// The path a sprout picks at level 15 (Flyff's first job change).
public enum PlayerClass: String, Codable, Sendable, CaseIterable {
    case guardian
    case thornshot
    case sporecaster
    case dewkeeper
}

public struct ClassDefinition: Sendable {
    public let id: PlayerClass
    public let name: String
    public let role: String
    public let description: String
    public let hpScale: Float
    public let mpScale: Float
    public let attackScale: Float
    public let defenseScale: Float
    /// Auto-attack reach in meters (edge to edge). Above ~2 m the class fights at range.
    public let reach: Float
    public let skills: [SkillID]

    public var isRanged: Bool { reach > 2 }
}

extension PlayerClass {
    public static let requiredLevel = 15

    public var definition: ClassDefinition {
        switch self {
        case .guardian:
            ClassDefinition(
                id: self, name: "Guard", role: "Tank",
                description: "Thick bark, thicker skull. Soaks up hits and slams crowds.",
                hpScale: 1.35, mpScale: 1, attackScale: 1, defenseScale: 1.5, reach: 0.9,
                skills: [.barkSkin, .capSlam])
        case .thornshot:
            ClassDefinition(
                id: self, name: "Thornshot", role: "Ranged",
                description: "Flings thorns from a safe distance. Several at once, if asked nicely.",
                hpScale: 1, mpScale: 1.1, attackScale: 1.2, defenseScale: 1, reach: 7,
                skills: [.thornVolley, .pinningShot])
        case .sporecaster:
            ClassDefinition(
                id: self, name: "Sporecaster", role: "Area caster",
                description: "Bends the fen's spores to their will. Fragile, but explosive.",
                hpScale: 0.9, mpScale: 1.7, attackScale: 1.3, defenseScale: 0.85, reach: 6,
                skills: [.sporeNova, .myceliumSurge])
        case .dewkeeper:
            ClassDefinition(
                id: self, name: "Dewkeeper", role: "Healer",
                description: "Calls the morning dew to mend wounds and lift spirits.",
                hpScale: 1.1, mpScale: 1.5, attackScale: 0.95, defenseScale: 1.1, reach: 6,
                skills: [.morningDew, .rainBlessing])
        }
    }
}
