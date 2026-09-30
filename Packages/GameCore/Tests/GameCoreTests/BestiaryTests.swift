import Foundation
import Testing
@testable import GameCore

/// Checks that the mobs, zones, loot, and quests fit together.
@Suite struct BestiaryTests {
    /// Mobs that only appear when something else summons or spawns them.
    private let summoned: Set<MobKind> = [.sporeling, .puffling, .mouse, .owl]

    @Test func everyMobLivesInOneZoneThatMatchesItsLevel() throws {
        let map = WorldMap.mushroomHollow
        for kind in MobKind.allCases where !summoned.contains(kind) {
            let areas = map.mobSpawns.filter { $0.kind == kind }
            #expect(areas.count == 1, "\(kind) has one spawn area")
            let area = try #require(areas.first)
            #expect(area.center.length + area.radius < map.boundaryRadius, "\(kind) spawns inside the world")
            let zone = try #require(map.zone(at: area.center))
            let levels = try #require(zone.levels, "\(kind) lives in a hunting ground, not \(zone.name)")
            #expect(levels.contains(kind.stats.level), "\(kind) (Lv \(kind.stats.level)) fits \(zone.name) \(levels)")
        }
    }

    @Test func zonesDoNotOverlap() {
        let zones = WorldMap.mushroomHollow.zones.filter { $0.levels != nil || $0.name == "Capstone Village" }
        for (i, a) in zones.enumerated() {
            for b in zones[(i + 1)...] {
                #expect(a.center.distance(to: b.center) >= a.radius + b.radius - 1, "\(a.name) and \(b.name) overlap")
            }
        }
    }

    @Test func everyMobDropsItsOwnMaterial() {
        for kind in MobKind.allCases where kind != .mouse && kind != .sporeling {
            let materials = kind.drops.filter {
                if case .material = $0.item.definition.kind { $0.item != .amberShard && $0.item != .wardCharm } else { false }
            }
            #expect(!materials.isEmpty, "\(kind) drops a material")
        }
    }

    @Test func everyPieceOfGearCanBeFound() {
        let sold = Set(NPCID.allCases.flatMap(\.definition.shopStock))
        let dropped = Set(MobKind.allCases.flatMap { $0.drops.map(\.item) })
        let rewarded = Set(QuestID.allCases.flatMap { $0.definition.rewardItems.map(\.item) })
        let classSets = Set(PlayerClass.allCases.compactMap(ItemSet.forClass).flatMap(\.definition.pieces))
        for item in ItemID.allCases where item.definition.equipSlot != nil {
            #expect(sold.contains(item) || dropped.contains(item) || rewarded.contains(item) || classSets.contains(item),
                    "\(item) has a source")
        }
    }

    @Test func theThistledownSetIsSpreadAcrossTheOuterRing() throws {
        let map = WorldMap.mushroomHollow
        var zones: [String] = []
        for piece in ItemSet.thistledown.definition.pieces {
            let sources = MobKind.allCases.filter { kind in kind.drops.contains { $0.item == piece } }
            #expect(sources.count == 1, "\(piece) drops from one mob")
            let source = try #require(sources.first)
            let area = try #require(map.mobSpawns.first { $0.kind == source })
            zones.append(try #require(map.zone(at: area.center)).name)
            #expect(source.drops.first { $0.item == piece }!.chance <= 0.01, "set pieces are very rare")
        }
        #expect(Set(zones).count == 4, "one piece per zone")
    }

    @Test func outerRingQuestsPointAtRealMobsAndDrops() {
        let spawned = Set(WorldMap.mushroomHollow.mobSpawns.map(\.kind))
        for quest in QuestID.allCases where quest != .hollowOwl {
            switch quest.definition.objective {
            case let .defeat(kind, _):
                #expect(spawned.contains(kind), "\(quest) hunts a mob that spawns")
            case let .collect(item, _):
                let droppers = MobKind.allCases.filter { kind in kind.drops.contains { $0.item == item } }
                #expect(droppers.contains { spawned.contains($0) }, "\(quest) collects something that drops")
            case let .explore(places):
                #expect(places.allSatisfy { WorldMap.mushroomHollow.landmark($0) != nil }, "\(quest) visits places on the map")
            case let .defeatGiant(minLevel, _):
                #expect(QuestObjective.giantKinds(minLevel: minLevel).contains { spawned.contains($0) }, "\(quest) has Giants to fight")
            }
        }
        #expect(QuestObjective.defeat(.mantis, count: 8).summary == "Defeat 8 Orchid Mantises")
    }

    @Test func tougherMobsPayMore() {
        let wild = MobKind.allCases.filter { !summoned.contains($0) }.sorted { $0.stats.level < $1.stats.level }
        for (weaker, stronger) in zip(wild, wild.dropFirst()) where weaker.stats.level < stronger.stats.level {
            #expect(weaker.stats.xp < stronger.stats.xp, "\(stronger) pays more XP than \(weaker)")
            #expect(weaker.capsDrop.upperBound <= stronger.capsDrop.upperBound, "\(stronger) drops more caps than \(weaker)")
        }
    }
}
