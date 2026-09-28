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
        case .mossBoots: "shoeprints.fill"
        case .dandelionSeed: "wind"
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
    var statLine: String? {
        let definition = definition
        switch definition.kind {
        case let .consumable(.restoreHP(amount)): return "Restores \(amount) HP"
        case let .consumable(.restoreMP(amount)): return "Restores \(amount) MP"
        case .material: return nil
        case .glider: return "Lets you fly" 
        case let .equipment(_, bonus):
            var parts: [String] = []
            if bonus.attack > 0 { parts.append("+\(bonus.attack) ATK") }
            if bonus.defense > 0 { parts.append("+\(bonus.defense) DEF") }
            if bonus.maxHP > 0 { parts.append("+\(bonus.maxHP) HP") }
            if bonus.maxMP > 0 { parts.append("+\(bonus.maxMP) MP") }
            if bonus.block > 0 { parts.append("\(Int((bonus.block * 100).rounded()))% Block") }
            return parts.joined(separator: " · ")
        }
    }
}

extension EquipSlot {
    var displayName: String {
        switch self {
        case .weapon: "Weapon"
        case .shield: "Shield"
        case .hat: "Hat"
        case .body: "Body"
        case .boots: "Boots"
        }
    }

    var placeholderSymbol: String {
        switch self {
        case .weapon: "wand.and.rays"
        case .shield: "shield"
        case .hat: "crown"
        case .body: "tshirt"
        case .boots: "shoeprints.fill"
        }
    }
}

extension NPCID {
    var symbol: String {
        switch self {
        case .elderMorel: "text.book.closed.fill"
        case .chanterelle: "bag.fill"
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
