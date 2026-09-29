import GameCore
import UIKit

/// Capstone Town's folk: Flyff-style humanoids on Sprout's body, each wearing the mushroom cap
/// they're named after, and holding (or wearing) the tools of their trade.
extension NPCID {
    var look: PlayerRig.Look {
        var look = PlayerRig.Look()
        look.sprout = false
        look.scarf = false
        switch self {
        case .elderMorel:
            look.hair = UIColor(white: 0.92, alpha: 1)
            look.beard = UIColor(white: 0.95, alpha: 1)
            look.longBeard = true
            look.tunic = UIColor(red: 0.45, green: 0.42, blue: 0.55, alpha: 1)
            look.trim = UIColor(red: 0.85, green: 0.75, blue: 0.45, alpha: 1)
            look.legs = UIColor(red: 0.3, green: 0.28, blue: 0.36, alpha: 1)
            look.cap = .morel(Palette.capBrown)
        case .chanterelle:
            look.hair = UIColor(red: 0.85, green: 0.42, blue: 0.18, alpha: 1)
            look.tunic = UIColor(red: 0.98, green: 0.9, blue: 0.75, alpha: 1)
            look.trim = UIColor(red: 0.98, green: 0.62, blue: 0.15, alpha: 1)
            look.legs = UIColor(red: 0.55, green: 0.35, blue: 0.2, alpha: 1)
            look.cap = .funnel(UIColor(red: 0.98, green: 0.62, blue: 0.15, alpha: 1))
        case .shiitake:
            look.hair = UIColor(red: 0.25, green: 0.16, blue: 0.1, alpha: 1)
            look.beard = UIColor(red: 0.25, green: 0.16, blue: 0.1, alpha: 1)
            look.tunic = UIColor(red: 0.36, green: 0.22, blue: 0.14, alpha: 1)
            look.trim = Palette.darkBark
            look.legs = UIColor(red: 0.25, green: 0.2, blue: 0.18, alpha: 1)
            look.cap = .wide(UIColor(red: 0.42, green: 0.26, blue: 0.16, alpha: 1))
        case .truffle:
            look.hair = UIColor(red: 0.2, green: 0.14, blue: 0.12, alpha: 1)
            look.tunic = UIColor(red: 0.35, green: 0.6, blue: 0.35, alpha: 1)
            look.trim = UIColor(red: 0.95, green: 0.92, blue: 0.82, alpha: 1)
            look.cap = .beret(UIColor(red: 0.28, green: 0.2, blue: 0.16, alpha: 1), spots: false)
        case .porcini:
            look.hair = UIColor(red: 0.5, green: 0.33, blue: 0.2, alpha: 1)
            look.tunic = UIColor(red: 0.36, green: 0.46, blue: 0.3, alpha: 1)
            look.trim = UIColor(red: 0.78, green: 0.6, blue: 0.4, alpha: 1)
            look.cap = .beret(UIColor(red: 0.55, green: 0.33, blue: 0.17, alpha: 1), spots: false)
        case .oyster:
            look.hair = UIColor(red: 0.3, green: 0.35, blue: 0.5, alpha: 1)
            look.tunic = UIColor(red: 0.3, green: 0.4, blue: 0.62, alpha: 1)
            look.trim = UIColor(red: 0.85, green: 0.85, blue: 0.9, alpha: 1)
            look.cap = .fan(UIColor(red: 0.78, green: 0.8, blue: 0.86, alpha: 1))
        case .enoki:
            look.hair = UIColor(red: 0.95, green: 0.92, blue: 0.82, alpha: 1)
            look.cap = .cluster(UIColor(red: 0.98, green: 0.96, blue: 0.88, alpha: 1))
        case .maitake:
            look.hair = UIColor(red: 0.35, green: 0.25, blue: 0.18, alpha: 1)
            look.tunic = UIColor(red: 0.62, green: 0.52, blue: 0.4, alpha: 1)
            look.trim = UIColor(red: 0.9, green: 0.85, blue: 0.7, alpha: 1)
            look.cap = .frills(UIColor(red: 0.5, green: 0.38, blue: 0.26, alpha: 1))
        }
        return look
    }

    /// What they wear and hold (drawn only; NPCs don't fight).
    var outfit: [ItemID] {
        switch self {
        case .elderMorel: [.dewdropStaff, .rainpetalGown]
        case .chanterelle: [.leafTunic]
        case .shiitake: [.pebbleHatchet, .chitinGauntlets]
        case .truffle: [.grassMitts]
        case .porcini: [.thistledownCoat]
        case .oyster: [.thornRapier, .barkBuckler]
        case .enoki: [.barkMail, .barkTreads]
        case .maitake: []
        }
    }

    @MainActor
    func makeRig() -> PlayerRig {
        let rig = PlayerRig(look: look)
        rig.dress(outfit, playerClass: nil)
        return rig
    }
}
