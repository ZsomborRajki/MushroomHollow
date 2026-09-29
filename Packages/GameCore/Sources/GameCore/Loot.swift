struct DropEntry: Sendable {
    let item: ItemID
    let chance: Float
    let count: ClosedRange<Int>
}

extension MobKind {
    /// A pile of caps drops only this often: in the Hollow, as in Flyff, money comes from quests,
    /// hunting requests, and selling what you find, not from the critters' pockets.
    static let capsDropChance: Float = 0.4

    /// The size of one caps pile: a few caps per level of the mob.
    var capsDrop: ClosedRange<Int> {
        switch self {
        case .owl: return 150...250
        case .sporeling, .puffling, .mouse: return 1...2
        default:
            let level = stats.level
            return max(1, level * 2 / 3)...(level + 1)
        }
    }

    /// Standard gear drops from mobs of its level (as in early Flyff). Set pieces are very rare:
    /// the Dewleaf set is spread over the zones from level 1 to 15, one piece per zone, and the
    /// Thistledown set over the first four zones of the outer ring.
    /// Whether this mob can drop `item` (for pointing players at the right hunting ground).
    public func canDrop(_ item: ItemID) -> Bool {
        drops.contains { $0.item == item }
    }

    var drops: [DropEntry] {
        switch self {
        case .snail:
            [DropEntry(item: .snailShell, chance: 0.6, count: 1...1),
             DropEntry(item: .dewPotion, chance: 0.08, count: 1...1),
             DropEntry(item: .mossBoots, chance: 0.02, count: 1...1),
             DropEntry(item: .twigSword, chance: 0.02, count: 1...1),
             DropEntry(item: .barkBuckler, chance: 0.02, count: 1...1),
             DropEntry(item: .grassMitts, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.03, count: 1...1),
             DropEntry(item: .dewleafSlippers, chance: 0.01, count: 1...1)]
        case .slug:
            [DropEntry(item: .slugSlime, chance: 0.55, count: 1...2),
             DropEntry(item: .dewPotion, chance: 0.1, count: 1...1),
             DropEntry(item: .nectarVial, chance: 0.08, count: 1...1),
             DropEntry(item: .acornCap, chance: 0.03, count: 1...1),
             DropEntry(item: .pebbleHatchet, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.04, count: 1...1),
             DropEntry(item: .dewleafCap, chance: 0.01, count: 1...1)]
        case .beetle:
            [DropEntry(item: .beetleHorn, chance: 0.5, count: 1...1),
             DropEntry(item: .dewPotion, chance: 0.12, count: 1...2),
             DropEntry(item: .beetleHelm, chance: 0.03, count: 1...1),
             DropEntry(item: .thornRapier, chance: 0.03, count: 1...1),
             DropEntry(item: .hornCleaver, chance: 0.03, count: 1...1),
             DropEntry(item: .beetleAegis, chance: 0.02, count: 1...1),
             DropEntry(item: .chitinGauntlets, chance: 0.03, count: 1...1),
             DropEntry(item: .barkTreads, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.06, count: 1...1),
             DropEntry(item: .wardCharm, chance: 0.002, count: 1...1),
             DropEntry(item: .dewleafGloves, chance: 0.01, count: 1...1)]
        case .sporeBeast:
            [DropEntry(item: .sporeSac, chance: 0.55, count: 1...2),
             DropEntry(item: .nectarVial, chance: 0.15, count: 1...2),
             DropEntry(item: .beetleBlade, chance: 0.03, count: 1...1),
             DropEntry(item: .barkMail, chance: 0.02, count: 1...1),
             DropEntry(item: .toadstoolChopper, chance: 0.03, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.08, count: 1...2),
             DropEntry(item: .wardCharm, chance: 0.004, count: 1...1),
             DropEntry(item: .dewleafVest, chance: 0.01, count: 1...1)]
        case .ladybug:
            [DropEntry(item: .spottedWingCase, chance: 0.6, count: 1...1),
             DropEntry(item: .dewPotion, chance: 0.08, count: 1...1),
             DropEntry(item: .grassMitts, chance: 0.02, count: 1...1),
             DropEntry(item: .acornCap, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.03, count: 1...1)]
        case .pillBug:
            [DropEntry(item: .pillBugPlate, chance: 0.55, count: 1...1),
             DropEntry(item: .dewPotion, chance: 0.1, count: 1...1),
             DropEntry(item: .shellShield, chance: 0.02, count: 1...1),
             DropEntry(item: .leafTunic, chance: 0.02, count: 1...1),
             DropEntry(item: .thornRapier, chance: 0.015, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.05, count: 1...1)]
        case .acornling:
            [DropEntry(item: .bitterAcorn, chance: 0.5, count: 1...2),
             DropEntry(item: .dewPotion, chance: 0.12, count: 1...1),
             DropEntry(item: .nectarVial, chance: 0.08, count: 1...1),
             DropEntry(item: .barkMail, chance: 0.03, count: 1...1),
             DropEntry(item: .hornCleaver, chance: 0.02, count: 1...1),
             DropEntry(item: .chitinGauntlets, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.06, count: 1...1)]
        case .aphid:
            [DropEntry(item: .honeydewDrop, chance: 0.6, count: 1...1),
             DropEntry(item: .dewPotion, chance: 0.08, count: 1...1),
             DropEntry(item: .pebbleHatchet, chance: 0.02, count: 1...1),
             DropEntry(item: .leafTunic, chance: 0.02, count: 1...1),
             DropEntry(item: .mossBoots, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.03, count: 1...1)]
        case .earthworm:
            [DropEntry(item: .richLoam, chance: 0.55, count: 1...1),
             DropEntry(item: .dewPotion, chance: 0.1, count: 1...1),
             DropEntry(item: .blinkwing, chance: 0.04, count: 1...1),
             DropEntry(item: .shellShield, chance: 0.02, count: 1...1),
             DropEntry(item: .barkTreads, chance: 0.02, count: 1...1),
             DropEntry(item: .hornCleaver, chance: 0.015, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.05, count: 1...1)]
        case .cricket:
            [DropEntry(item: .cricketLeg, chance: 0.5, count: 1...2),
             DropEntry(item: .sapTonic, chance: 0.1, count: 1...1),
             DropEntry(item: .nectarVial, chance: 0.08, count: 1...1),
             DropEntry(item: .beetleAegis, chance: 0.02, count: 1...1),
             DropEntry(item: .toadstoolChopper, chance: 0.02, count: 1...1),
             DropEntry(item: .frogHoppers, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.07, count: 1...1),
             DropEntry(item: .wardCharm, chance: 0.003, count: 1...1)]
        case .bogFrog:
            [DropEntry(item: .frogJelly, chance: 0.5, count: 1...2),
             DropEntry(item: .nectarVial, chance: 0.12, count: 1...1),
             DropEntry(item: .lilypadTarge, chance: 0.03, count: 1...1),
             DropEntry(item: .frogHoppers, chance: 0.03, count: 1...1),
             DropEntry(item: .toadstoolChopper, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.08, count: 1...1),
             DropEntry(item: .wardCharm, chance: 0.004, count: 1...1)]

        // The outer ring. Each mob drops the next tier of common gear, and in the first four zones
        // one Thistledown piece.
        case .fuzzbee:
            [DropEntry(item: .honeycombChip, chance: 0.5, count: 1...2),
             DropEntry(item: .sapTonic, chance: 0.15, count: 1...2),
             DropEntry(item: .stingerBlade, chance: 0.03, count: 1...1),
             DropEntry(item: .honeycombHelm, chance: 0.03, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.08, count: 1...1),
             DropEntry(item: .wardCharm, chance: 0.005, count: 1...1)]
        case .puffweed:
            [DropEntry(item: .pollenPuff, chance: 0.55, count: 1...2),
             DropEntry(item: .nectarVial, chance: 0.15, count: 1...2),
             DropEntry(item: .buttercupStaff, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.08, count: 1...1),
             DropEntry(item: .thistledownCap, chance: 0.01, count: 1...1)]
        case .puffling:
            [DropEntry(item: .pollenPuff, chance: 0.15, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.02, count: 1...1)]
        case .mossTurtle:
            [DropEntry(item: .mossyScute, chance: 0.55, count: 1...1),
             DropEntry(item: .sapTonic, chance: 0.15, count: 1...2),
             DropEntry(item: .mossbackCleaver, chance: 0.03, count: 1...1),
             DropEntry(item: .mossbackShield, chance: 0.03, count: 1...1),
             DropEntry(item: .turtleshellMail, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.09, count: 1...2),
             DropEntry(item: .wardCharm, chance: 0.006, count: 1...1)]
        case .emberNewt:
            [DropEntry(item: .emberScale, chance: 0.5, count: 1...2),
             DropEntry(item: .moonNectar, chance: 0.15, count: 1...2),
             DropEntry(item: .emberstoneMaul, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.09, count: 1...2),
             DropEntry(item: .thistledownCoat, chance: 0.01, count: 1...1)]
        case .weaverSpider:
            [DropEntry(item: .spiderSilk, chance: 0.55, count: 1...2),
             DropEntry(item: .sapTonic, chance: 0.15, count: 1...2),
             DropEntry(item: .silkfangSaber, chance: 0.03, count: 1...1),
             DropEntry(item: .silkstringBow, chance: 0.02, count: 1...1),
             DropEntry(item: .silkweaveGloves, chance: 0.03, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.1, count: 1...2),
             DropEntry(item: .wardCharm, chance: 0.007, count: 1...1)]
        case .duskMoth:
            [DropEntry(item: .mothDust, chance: 0.55, count: 1...2),
             DropEntry(item: .moonNectar, chance: 0.18, count: 1...2),
             DropEntry(item: .mothwingWand, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.1, count: 1...2),
             DropEntry(item: .thistledownGloves, chance: 0.01, count: 1...1)]
        case .hedgehog:
            [DropEntry(item: .hedgehogQuill, chance: 0.55, count: 1...2),
             DropEntry(item: .honeydewDraught, chance: 0.18, count: 1...2),
             DropEntry(item: .quillsplitter, chance: 0.03, count: 1...1),
             DropEntry(item: .quilledBoots, chance: 0.03, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.1, count: 1...2),
             DropEntry(item: .wardCharm, chance: 0.008, count: 1...1),
             DropEntry(item: .thistledownBoots, chance: 0.01, count: 1...1)]
        case .coneKnight:
            [DropEntry(item: .pineScale, chance: 0.55, count: 1...2),
             DropEntry(item: .moonNectar, chance: 0.18, count: 1...2),
             DropEntry(item: .pineconeHelm, chance: 0.03, count: 1...1),
             DropEntry(item: .pineconeBulwark, chance: 0.03, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.11, count: 1...2),
             DropEntry(item: .wardCharm, chance: 0.008, count: 1...1)]
        case .mantis:
            [DropEntry(item: .mantisClaw, chance: 0.5, count: 1...2),
             DropEntry(item: .honeydewDraught, chance: 0.2, count: 1...2),
             DropEntry(item: .mantisEdge, chance: 0.03, count: 1...1),
             DropEntry(item: .mantisLongbow, chance: 0.02, count: 1...1),
             DropEntry(item: .mantisCarapace, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.12, count: 1...2),
             DropEntry(item: .wardCharm, chance: 0.01, count: 1...1)]
        case .thornrose:
            [DropEntry(item: .roseHip, chance: 0.55, count: 1...2),
             DropEntry(item: .moonNectar, chance: 0.2, count: 1...2),
             DropEntry(item: .thornroseStaff, chance: 0.02, count: 1...1),
             DropEntry(item: .rosethornGauntlets, chance: 0.03, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.12, count: 1...2),
             DropEntry(item: .wardCharm, chance: 0.01, count: 1...1)]
        case .grumblecap:
            [DropEntry(item: .grumbleSpore, chance: 0.55, count: 1...2),
             DropEntry(item: .moonNectar, chance: 0.2, count: 1...2),
             DropEntry(item: .grumblecapScepter, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.13, count: 1...2),
             DropEntry(item: .wardCharm, chance: 0.01, count: 1...1)]
        case .stagBeetle:
            [DropEntry(item: .stagMandible, chance: 0.5, count: 1...2),
             DropEntry(item: .honeydewDraught, chance: 0.2, count: 1...3),
             DropEntry(item: .stagjawAxe, chance: 0.03, count: 1...1),
             DropEntry(item: .stagCrusher, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.15, count: 1...3),
             DropEntry(item: .wardCharm, chance: 0.012, count: 1...1)]
        case .sporeling:
            [DropEntry(item: .sporeSac, chance: 0.1, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.02, count: 1...1)]
        case .mouse:
            [DropEntry(item: .dewPotion, chance: 0.15, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.03, count: 1...1)]
        case .owl:
            [DropEntry(item: .owlFeather, chance: 1, count: 2...4),
             DropEntry(item: .moonTalon, chance: 0.35, count: 1...1),
             DropEntry(item: .featherCloak, chance: 0.35, count: 1...1),
             DropEntry(item: .boughHammer, chance: 0.12, count: 1...1),
             DropEntry(item: .owlboneBow, chance: 0.12, count: 1...1),
             DropEntry(item: .glowcapScepter, chance: 0.12, count: 1...1),
             DropEntry(item: .raincallerStaff, chance: 0.12, count: 1...1),
             DropEntry(item: .amberShard, chance: 1, count: 3...6),
             DropEntry(item: .wardCharm, chance: 0.3, count: 1...1),
             DropEntry(item: .nectarVial, chance: 1, count: 3...5)]
        }
    }

    /// Chance to drop one random piece of the killer's class set (classed players only).
    var classSetChance: Float {
        switch self {
        case .owl: 0.3
        case .stagBeetle: 0.008
        case .coneKnight, .mantis, .thornrose, .grumblecap: 0.006
        case .emberNewt, .weaverSpider, .duskMoth, .hedgehog: 0.005
        case .sporeBeast, .fuzzbee, .puffweed, .mossTurtle: 0.004
        case .mouse: 0.003
        case .snail, .slug, .beetle, .sporeling, .ladybug, .pillBug, .acornling, .bogFrog, .puffling,
             .aphid, .earthworm, .cricket: 0
        }
    }
}

struct GroundDrop: Sendable {
    let id: UInt32
    let owner: EntityID
    let position: Vec2
    var kind: GroundDropKind
    let availableAtTick: UInt64
    let expiresAtTick: UInt64
}

extension GameSimulation {
    static let dropPickupRadius: Float = 1.5
    static let dropPickupDelayTicks = ticks(0.75)
    static let dropLifetimeTicks = ticks(180)

    /// Mobs this many levels below the player drop only their material (and rarely): no caps, gear, or amber.
    static let outlevelledGap = 8

    /// Rolls rewards at the defeated mob's position. Boss participants receive separate personal drops.
    mutating func rollLoot(for kind: MobKind, giant: Bool = false, ownedBy player: WorldEntity, at origin: Vec2) {
        guard let data = player.player else { return }
        if !giant, player.stats.level - kind.stats.level >= Self.outlevelledGap {
            if let material = kind.drops.first, random.unit() < material.chance / 2 {
                spawnDrop(.item(material.item, count: 1), for: player.id, at: origin)
            }
            return
        }
        if giant || random.unit() < MobKind.capsDropChance {
            let pile = random.int(in: kind.capsDrop)
            spawnDrop(.caps(giant ? pile * Giant.capsMultiplier : pile), for: player.id, at: origin)
        }
        for _ in 0..<(giant ? Giant.lootRolls : 1) {
            for entry in kind.drops where random.unit() < entry.chance {
                spawnDrop(.item(entry.item, count: random.int(in: entry.count)), for: player.id, at: origin)
            }
        }
        if giant {
            // A Giant always leaves a piece of its field's gear behind.
            let gear = kind.drops.filter { $0.item.definition.equipSlot != nil }
            if !gear.isEmpty {
                spawnDrop(.item(gear[random.int(in: 0...(gear.count - 1))].item, count: 1), for: player.id, at: origin)
            }
        }
        let setChance = kind.classSetChance * (giant ? Giant.classSetMultiplier : 1)
        if let job = data.playerClass, let set = ItemSet.forClass(job), setChance > 0, random.unit() < setChance {
            let pieces = set.definition.pieces
            spawnDrop(.item(pieces[random.int(in: 0...(pieces.count - 1))], count: 1), for: player.id, at: origin)
        }
    }

    private mutating func spawnDrop(_ kind: GroundDropKind, for owner: EntityID, at origin: Vec2) {
        nextDropID += 1
        let offset = random.point(inDiscAt: .zero, radius: 1.0)
        let position = map.resolve(origin + offset, radius: 0.15)
        drops.append(GroundDrop(id: nextDropID, owner: owner, position: position, kind: kind,
                                availableAtTick: tick + UInt64(Self.dropPickupDelayTicks),
                                expiresAtTick: tick + UInt64(Self.dropLifetimeTicks)))
    }

    /// Returns a failure only for explicit pickup attempts; automatic collection ignores full bags.
    mutating func collectDrop(_ id: UInt32, for player: inout WorldEntity) -> ActionFailure? {
        guard let index = drops.firstIndex(where: { $0.id == id }), drops[index].owner == player.id else { return .notAvailable }
        guard player.stats.isAlive, player.position.y <= Self.reachableAltitude,
              player.position.xz.distance(to: drops[index].position) <= Self.dropPickupRadius
        else { return .tooFar }
        return grantDrop(at: index, to: &player)
    }

    /// Hands a drop to its owner, whoever picked it up (the owner or their pet).
    mutating func grantDrop(at index: Int, to player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player else { return .notAvailable }
        switch drops[index].kind {
        case let .caps(amount):
            data.caps += amount
            events.append(.capsChanged(player: player.id, delta: amount))
            drops.remove(at: index)
        case let .item(item, count):
            let leftover = data.inventory.add(item, count: count)
            guard leftover < count else { return .inventoryFull }
            events.append(.itemReceived(player: player.id, item: item, count: count - leftover))
            if leftover == 0 {
                drops.remove(at: index)
            } else {
                drops[index].kind = .item(item, count: leftover)
            }
        }
        player.player = data
        reportCollectProgress(for: &player)
        return nil
    }

    mutating func stepDrops() {
        drops.removeAll { tick >= $0.expiresAtTick }
        let nearby = drops.compactMap { drop -> UInt32? in
            guard tick >= drop.availableAtTick, let owner = entities[drop.owner], owner.stats.isAlive,
                  owner.position.y <= Self.reachableAltitude,
                  owner.position.xz.distance(to: drop.position) <= Self.dropPickupRadius else { return nil }
            return drop.id
        }
        for id in nearby {
            guard let drop = drops.first(where: { $0.id == id }), var owner = entities[drop.owner] else { continue }
            if collectDrop(id, for: &owner) == nil { entities[owner.id] = owner }
        }
    }
}
