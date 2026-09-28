import GameCore
import SwiftUI

/// Client-only look of items, NPCs, quests, and failure messages.
extension ItemID {
    var symbol: String {
        switch self {
        case .dewPotion: "cross.vial.fill"
        case .nectarVial: "waterbottle.fill"
        case .snailShell: "hurricane"
        case .slugSlime: "humidity.fill"
        case .beetleHorn: "arrowtriangle.up.fill"
        case .sporeSac: "circle.hexagongrid.fill"
        case .owlFeather: "bird.fill"
        case .moonTalon: "moon.fill"
        case .featherCloak: "tshirt.fill"
        case .twigSword: "line.diagonal"
        case .thornRapier: "wand.and.rays"
        case .beetleBlade: "bolt.fill"
        case .pebbleHatchet, .hornCleaver, .toadstoolChopper: "hammer.fill"
        case .barkBuckler, .shellShield, .beetleAegis: "shield.fill"
        case .toadstoolMaul, .boughHammer: "hammer.circle.fill"
        case .reedBow, .owlboneBow: "scope"
        case .puffballWand, .glowcapScepter: "wand.and.stars"
        case .dewdropStaff, .raincallerStaff: "drop.fill"
        case .acornCap, .beetleHelm: "crown.fill"
        case .leafTunic, .barkMail: "tshirt.fill"
        case .mossBoots, .barkTreads: "shoeprints.fill"
        case .grassMitts, .chitinGauntlets: "hand.raised.fill"
        case .spottedWingCase: "ladybug.fill"
        case .pillBugPlate, .mossyScute, .pineScale: "hexagon.fill"
        case .bitterAcorn: "leaf.fill"
        case .frogJelly: "drop.circle.fill"
        case .honeycombChip: "circle.hexagongrid.fill"
        case .pollenPuff: "aqi.low"
        case .emberScale: "flame.fill"
        case .spiderSilk: "circle.dotted"
        case .mothDust: "sparkles"
        case .hedgehogQuill, .mantisClaw: "line.diagonal"
        case .roseHip: "camera.macro"
        case .grumbleSpore: "circle.hexagonpath.fill"
        case .stagMandible: "arrow.up.and.down.and.sparkles"
        case .stingerBlade, .silkfangSaber, .mantisEdge: "wand.and.rays"
        case .mossbackCleaver, .quillsplitter, .stagjawAxe: "hammer.fill"
        case .lilypadTarge, .mossbackShield, .pineconeBulwark: "shield.fill"
        case .emberstoneMaul, .stagCrusher: "hammer.circle.fill"
        case .silkstringBow, .mantisLongbow: "scope"
        case .mothwingWand, .grumblecapScepter: "wand.and.stars"
        case .buttercupStaff, .thornroseStaff: "camera.macro"
        case .amberShard: "diamond.fill"
        case .wardCharm: "seal.fill"
        case .dandelionSeed: "wind"
        case .pip: "dog.fill"
        case .kibble: "pawprint.circle.fill"
        default:
            // Set pieces: one icon per slot.
            switch definition.equipSlot {
            case .hat: "crown.fill"
            case .body: "tshirt.fill"
            case .gloves: "hand.raised.fill"
            default: "shoeprints.fill"
            }
        }
    }

    var tint: Color {
        switch self {
        case .dewPotion: .red
        case .nectarVial: .blue
        case .snailShell: Color(red: 0.8, green: 0.6, blue: 0.4)
        case .slugSlime: Color(red: 0.8, green: 0.8, blue: 0.3)
        case .beetleHorn: Color(red: 0.4, green: 0.55, blue: 0.95)
        case .sporeSac: .purple
        case .owlFeather, .featherCloak: Color(red: 0.85, green: 0.75, blue: 0.6)
        case .moonTalon: Color(red: 0.75, green: 0.85, blue: 1)
        case .twigSword, .leafTunic, .mossBoots: .green
        case .thornRapier, .acornCap: .orange
        case .beetleBlade, .beetleHelm: .cyan
        case .barkMail: .brown
        case .dandelionSeed: .white
        case .pebbleHatchet: Color(white: 0.75)
        case .hornCleaver, .beetleAegis: Color(red: 0.4, green: 0.55, blue: 0.95)
        case .toadstoolChopper, .toadstoolMaul: Color(red: 0.95, green: 0.35, blue: 0.3)
        case .barkBuckler: .brown
        case .shellShield: Color(red: 0.85, green: 0.6, blue: 0.35)
        case .boughHammer: Color(red: 0.45, green: 0.95, blue: 0.85)
        case .reedBow: Color(red: 0.75, green: 0.8, blue: 0.4)
        case .owlboneBow: Color(red: 0.95, green: 0.92, blue: 0.82)
        case .puffballWand: Color(red: 0.8, green: 0.55, blue: 1)
        case .glowcapScepter: Color(red: 0.45, green: 0.95, blue: 0.85)
        case .dewdropStaff, .raincallerStaff: Color(red: 0.55, green: 0.9, blue: 1)
        case .grassMitts: .green
        case .chitinGauntlets: Color(red: 0.4, green: 0.55, blue: 0.95)
        case .barkTreads: .brown
        case .spottedWingCase: .red
        case .pillBugPlate: Color(white: 0.65)
        case .bitterAcorn, .pineScale: Color(red: 0.7, green: 0.48, blue: 0.25)
        case .frogJelly, .lilypadTarge, .frogHoppers: Color(red: 0.45, green: 0.8, blue: 0.35)
        case .honeycombChip, .stingerBlade, .honeycombHelm, .buttercupStaff: Color(red: 1, green: 0.8, blue: 0.25)
        case .pollenPuff: Color(white: 0.95)
        case .mossyScute, .mossbackCleaver, .mossbackShield, .turtleshellMail: Color(red: 0.5, green: 0.62, blue: 0.3)
        case .emberScale, .emberstoneMaul: Color(red: 1, green: 0.5, blue: 0.2)
        case .spiderSilk, .silkfangSaber, .silkstringBow, .silkweaveGloves: Color(red: 0.8, green: 0.75, blue: 0.95)
        case .mothDust, .mothwingWand: Color(red: 0.72, green: 0.62, blue: 0.9)
        case .hedgehogQuill, .quillsplitter, .quilledBoots: Color(red: 0.6, green: 0.45, blue: 0.32)
        case .pineconeHelm, .pineconeBulwark: Color(red: 0.62, green: 0.42, blue: 0.24)
        case .mantisClaw, .mantisEdge, .mantisLongbow, .mantisCarapace: Color(red: 1, green: 0.7, blue: 0.82)
        case .roseHip, .thornroseStaff, .rosethornGauntlets: Color(red: 0.9, green: 0.25, blue: 0.38)
        case .grumbleSpore, .grumblecapScepter: Color(red: 0.95, green: 0.3, blue: 0.3)
        case .stagMandible, .stagjawAxe, .stagCrusher: Color(red: 0.55, green: 0.35, blue: 0.22)
        case .amberShard: Color(red: 1, green: 0.66, blue: 0.2)
        case .wardCharm: Color(red: 0.45, green: 0.95, blue: 0.85)
        case .pip: Color(red: 1, green: 0.85, blue: 0.6)
        case .kibble: Color(red: 0.85, green: 0.55, blue: 0.3)
        default: definition.set?.tint ?? .white
        }
    }

    /// e.g. "Axe · Two-handed · Guard only", for weapons and shields.
    var gearLine: String? {
        let definition = definition
        if definition.equipSlot == .shield { return "Shield" }
        guard let weapon = definition.weaponType else { return nil }
        var parts = [weapon.displayName]
        if weapon.isTwoHanded { parts.append("Two-handed") }
        if let required = definition.requiredClass { parts.append("\(required.definition.name) only") }
        return parts.joined(separator: " · ")
    }

    /// One-line stat summary for tooltips, e.g. "+4 ATK · +10 HP".
    var statLine: String? { Gear(self).statLine }
}

extension Gear {
    /// "Twig Sword +3".
    var displayName: String { upgrade > 0 ? "\(definition.name) +\(upgrade)" : definition.name }

    /// One-line stat summary including the upgrade, e.g. "+6 ATK · +10 HP".
    var statLine: String? {
        switch definition.kind {
        case let .consumable(.restoreHP(amount)): "Restores \(amount) HP"
        case let .consumable(.restoreMP(amount)): "Restores \(amount) MP"
        case .material: nil
        case .glider: "Lets you fly"
        case .pet: "Pet · fetches your drops"
        case .petFood: "Fills up your pet"
        case .equipment: bonus.summary
        }
    }
}

extension StatBonus {
    /// "+4 ATK · +10 HP · +15% Speed".
    var summary: String {
        var parts: [String] = []
        if attack > 0 { parts.append("+\(attack) ATK") }
        if defense > 0 { parts.append("+\(defense) DEF") }
        if maxHP > 0 { parts.append("+\(maxHP) HP") }
        if maxMP > 0 { parts.append("+\(maxMP) MP") }
        if block > 0 { parts.append("\(Self.percent(block)) Block") }
        if attackSpeed > 0 { parts.append("+\(Self.percent(attackSpeed)) Speed") }
        if critical > 0 { parts.append("+\(Self.percent(critical)) Crit") }
        return parts.joined(separator: " · ")
    }

    static func percent(_ value: Float) -> String { "\(Int((value * 100).rounded()))%" }
}

extension Rarity {
    /// Name color: white for standard gear, green for sets, gold for boss drops.
    var color: Color {
        switch self {
        case .common: .primary
        case .set: Color(red: 0.4, green: 0.95, blue: 0.45)
        case .unique: Color(red: 1, green: 0.78, blue: 0.3)
        }
    }
}

extension ItemSet {
    var tint: Color {
        switch self {
        case .dewleaf: Color(red: 0.45, green: 0.9, blue: 0.55)
        case .heartwood: Color(red: 0.75, green: 0.5, blue: 0.3)
        case .briar: Color(red: 0.55, green: 0.75, blue: 0.3)
        case .mycelium: Color(red: 0.8, green: 0.6, blue: 1)
        case .rainpetal: Color(red: 0.55, green: 0.85, blue: 1)
        case .thistledown: Color(red: 0.85, green: 0.78, blue: 1)
        }
    }
}

extension UpgradeResult {
    func message(for item: ItemID) -> String {
        let name = item.definition.name
        return switch self {
        case let .succeeded(level): "Success! \(name) is now +\(level)"
        case let .failed(level): "The upgrade failed. \(name) stays +\(level)"
        case let .protected(level): "Failed, but the Ward Charm held. \(name) stays +\(level)"
        case let .downgraded(level): "Failed! \(name) dropped to +\(level)"
        case .destroyed: "Failed! \(name) shattered"
        }
    }

    var succeeded: Bool {
        if case .succeeded = self { return true }
        return false
    }
}

extension EquipSlot {
    var displayName: String {
        switch self {
        case .weapon: "Weapon"
        case .shield: "Shield"
        case .hat: "Hat"
        case .body: "Body"
        case .gloves: "Gloves"
        case .boots: "Boots"
        }
    }

    var placeholderSymbol: String {
        switch self {
        case .weapon: "wand.and.rays"
        case .shield: "shield"
        case .hat: "crown"
        case .body: "tshirt"
        case .gloves: "hand.raised"
        case .boots: "shoeprints.fill"
        }
    }
}

extension NPCID {
    var symbol: String {
        switch self {
        case .elderMorel: "text.book.closed.fill"
        case .chanterelle: "bag.fill"
        case .shiitake: "hammer.fill"
        case .truffle: "pawprint.fill"
        case .porcini: "book.pages.fill"
        }
    }
}

extension ActionFailure {
    var message: String {
        switch self {
        case .tooFar: "Too far away"
        case .notEnoughCaps: "Not enough caps"
        case .inventoryFull: "Your bag is full"
        case .levelTooLow: "Your level is too low"
        case .missingItem: "You don't have that"
        case .notUsable: "You can't use that"
        case .notAvailable: "Not available"
        case .itemCooldown: "Not ready yet"
        case .wrongClass: "Your class can't use that"
        case .missingMaterials: "You need more Amber Shards"
        case .maxUpgrade: "Already +10"
        case .noPet: "Put a pet in your pet slot first"
        case .petHungry: "Too hungry to come out. Feed it Kibble"
        case .petFull: "Your pet is already full"
        case .noStatPoints: "No stat points left to spend"
        }
    }
}

extension WeaponType {
    var displayName: String {
        switch self {
        case .sword: "Sword"
        case .axe: "Axe"
        case .maul: "Maul"
        case .bow: "Bow"
        case .wand: "Wand"
        case .staff: "Staff"
        }
    }
}

extension QuestDefinition {
    var rewardLine: String {
        var parts = ["\(rewardXP) XP", "\(rewardCaps) caps"]
        parts += rewardItems.map { $0.count > 1 ? "\($0.item.definition.name) ×\($0.count)" : $0.item.definition.name }
        return parts.joined(separator: " · ")
    }
}

extension Attribute {
    var symbol: String {
        switch self {
        case .strength: "figure.strengthtraining.traditional"
        case .stamina: "heart.fill"
        case .dexterity: "hare.fill"
        case .intelligence: "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .strength: .red
        case .stamina: .orange
        case .dexterity: .green
        case .intelligence: .cyan
        }
    }

    /// What one point buys.
    var perPoint: String {
        switch self {
        case .strength: "+\(Self.decimal(Attributes.attackPerStrength)) ATK"
        case .stamina: "+\(Attributes.hpPerStamina) HP, +\(Self.decimal(Attributes.defensePerStamina)) DEF"
        case .dexterity: "+\(Self.decimal(Attributes.speedPerDexterity * 100))% speed, +\(Self.decimal(Attributes.criticalPerDexterity * 100))% crit"
        case .intelligence: "+\(Attributes.mpPerIntelligence) MP, +\(Self.decimal(Attributes.skillPowerPerIntelligence * 100))% skills"
        }
    }

    private static func decimal(_ value: Float) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%g", value)
    }
}
