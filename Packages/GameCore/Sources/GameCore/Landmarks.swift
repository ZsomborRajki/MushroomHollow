/// Named places worth a walk: hilltops, shores, old stones. Exploration quests (Flyff's patrol quests)
/// send you to them, and each has a signpost so you know when you've arrived.
/// Where they stand is part of the map (`WorldMap.landmarks`), so the sim and the client agree.
public enum LandmarkID: String, Codable, Sendable, CaseIterable {
    // Between the roots and the outer ring
    case cattailShore, sunnyHillock, cloverKnoll, oldKnot, barkfallBluff, foxgloveHill, owlwatchHill, fallenBough
    // The wild fringe past the outer ring
    case rimviewBluff, glimmerDell, windwhistlePeak, moonwellTarn, hollowlogCrossing, mossringStones

    public var name: String {
        switch self {
        case .cattailShore: "Cattail Shore"
        case .sunnyHillock: "Sunny Hillock"
        case .cloverKnoll: "Clover Knoll"
        case .oldKnot: "The Old Knot"
        case .barkfallBluff: "Barkfall Bluff"
        case .foxgloveHill: "Foxglove Hill"
        case .owlwatchHill: "Owlwatch Hill"
        case .fallenBough: "The Fallen Bough"
        case .rimviewBluff: "Rimview Bluff"
        case .glimmerDell: "Glimmer Dell"
        case .windwhistlePeak: "Windwhistle Peak"
        case .moonwellTarn: "Moonwell Tarn"
        case .hollowlogCrossing: "Hollowlog Crossing"
        case .mossringStones: "Mossring Stones"
        }
    }

    /// One line about the place, for the map and the arrival banner.
    public var blurb: String {
        switch self {
        case .cattailShore: "Dewdrop Lake's reedy north beach"
        case .sunnyHillock: "A warm hump of moss south of town"
        case .cloverKnoll: "A clover-topped hill east of the trunk"
        case .oldKnot: "A knot in the Great Tree as big as a house"
        case .barkfallBluff: "Bark flakes the size of roofs"
        case .foxgloveHill: "Foxgloves ring its wooded top"
        case .owlwatchHill: "You can see the Great Bough from here"
        case .fallenBough: "The branch the Hollow Owl perches by"
        case .rimviewBluff: "Where the south road ends and the rim begins"
        case .glimmerDell: "A hollow full of glowcaps"
        case .windwhistlePeak: "The highest hill under the tree"
        case .moonwellTarn: "A still, deep pond that holds the moon"
        case .hollowlogCrossing: "A fallen limb so big it's a landmark"
        case .mossringStones: "Old stones standing in a ring"
        }
    }
}

/// Where a landmark stands on the map. Being within `radius` of `position` counts as a visit.
public struct Landmark: Codable, Sendable {
    public let id: LandmarkID
    public let position: Vec2
    public let radius: Float

    public init(id: LandmarkID, position: Vec2, radius: Float = 8) {
        self.id = id
        self.position = position
        self.radius = radius
    }
}

extension WorldMap {
    public func landmark(_ id: LandmarkID) -> Landmark? {
        landmarks.first { $0.id == id }
    }
}

extension GameSimulation {
    /// Exploration quests tick off each place you set foot on (flying over doesn't count: land and look around).
    /// Progress is stored as a bitmask over the quest's places, so they can be visited in any order.
    mutating func recordVisits(_ player: inout WorldEntity) {
        guard var data = player.player, !data.activeQuests.isEmpty, player.stats.isAlive,
              player.position.y <= Self.reachableAltitude else { return }
        let here = player.position.xz
        for quest in QuestID.allCases {
            guard let visited = data.activeQuests[quest], case let .explore(places) = quest.definition.objective else { continue }
            var mask = visited
            for (index, place) in places.enumerated() where mask & (1 << index) == 0 {
                guard let landmark = map.landmark(place), landmark.position.distance(to: here) <= landmark.radius else { continue }
                mask |= 1 << index
            }
            guard mask != visited else { continue }
            data.activeQuests[quest] = mask
            events.append(.questProgress(player: player.id, quest: quest, progress: mask.nonzeroBitCount, goal: places.count))
        }
        player.player = data
    }

    /// The places an exploration quest still wants you to visit.
    func unvisitedPlaces(_ quest: QuestID, for player: WorldEntity) -> [LandmarkID] {
        guard case let .explore(places) = quest.definition.objective,
              let visited = player.player?.activeQuests[quest] else { return [] }
        return places.enumerated().filter { visited & (1 << $0.offset) == 0 }.map(\.element)
    }
}
