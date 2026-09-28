import GameCore
import RealityKit
import UIKit

/// A pet's model with the joints its procedural animation moves. Models face +Z, paws at y = 0.
@MainActor
final class PetRig {
    struct Motion {
        var moving: Bool
        var hungry: Bool
        var fetching: Bool
    }

    let root = Entity()
    /// Everything above the legs: bobs while trotting, settles back when idle.
    private let body = Entity()
    private let head = Entity()
    private let tail = Entity()
    private var ears: [(pivot: Entity, side: Float)] = []
    private var legs: [(pivot: Entity, phase: Float)] = []
    private var hopStart: Double?
    /// Eases between trotting and standing, so the gait doesn't snap.
    private var stride: Float = 0

    static let tint = UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1)

    init(_ kind: PetKind) {
        switch kind {
        case .pup: buildPup()
        }
    }

    /// A happy hop after picking something up.
    func playHop(at time: Double) {
        hopStart = time
    }

    func animate(_ motion: Motion, time: Double, seed: Float) {
        let t = Float(time)
        stride += ((motion.moving ? 1 : 0) - stride) * 0.2
        let gait = t * (motion.hungry ? 11 : 17) + seed

        // Trot: diagonal legs swing together, the body bobs twice per stride.
        for leg in legs {
            leg.pivot.orientation = simd_quatf(angle: sin(gait + leg.phase) * 0.7 * stride, axis: [1, 0, 0])
        }
        var bodyOffset = SIMD3<Float>(0, abs(sin(gait)) * 0.03 * stride, 0)
        // Standing still, the rear settles and the head tips up toward its owner.
        let settle = 1 - stride
        var bodyTilt = -0.12 * settle
        var headTilt: Float = motion.hungry ? 0.3 : -0.18 * settle + sin(t * 1.3 + seed) * 0.05
        if motion.fetching { headTilt = 0.35 } // nose to the ground

        if let start = hopStart {
            let p = Float((time - start) / 0.45)
            if p < 1 {
                bodyOffset.y += sin(p * .pi) * 0.16
                bodyTilt -= sin(p * .pi) * 0.3
                headTilt -= sin(p * .pi) * 0.3
            } else {
                hopStart = nil
            }
        }
        body.position = bodyOffset
        body.orientation = simd_quatf(angle: bodyTilt, axis: [1, 0, 0])
        head.orientation = simd_quatf(angle: headTilt, axis: [1, 0, 0])
            * simd_quatf(angle: sin(t * 0.9 + seed) * 0.12 * settle, axis: [0, 0, 1]) // a curious head tilt

        // Floppy ears bounce with the trot; a hungry pup's hang flat and sad.
        for ear in ears {
            let lift: Float = motion.hungry ? 0.02 : 0.3 + sin(gait * 2 + ear.side) * 0.2 * stride
            ear.pivot.orientation = simd_quatf(angle: ear.side * lift, axis: [0, 0, 1])
                * simd_quatf(angle: motion.hungry ? 0.35 : 0, axis: [1, 0, 0])
        }
        // Wagging, fast when happy, a slow droop when hungry.
        let wag = motion.hungry ? sin(t * 3 + seed) * 0.15 : sin(t * (motion.fetching ? 24 : 15) + seed) * 0.65
        tail.orientation = simd_quatf(angle: wag, axis: [0, 1, 0])
            * simd_quatf(angle: motion.hungry ? -0.7 : 0.75, axis: [1, 0, 0]) // up when happy, tucked down when hungry
    }

    /// Pip: a cream pup with tan floppy ears, a tan patch, white socks, and a leaf-green bandana.
    private func buildPup() {
        let cream = Materials.matte(UIColor(red: 1, green: 0.91, blue: 0.76, alpha: 1), roughness: 1)
        let tan = Materials.matte(UIColor(red: 0.86, green: 0.58, blue: 0.34, alpha: 1), roughness: 1)
        let sock = Materials.matte(UIColor(red: 1, green: 0.98, blue: 0.93, alpha: 1), roughness: 1)
        let nose = Materials.glossy(UIColor(red: 0.2, green: 0.13, blue: 0.11, alpha: 1))
        let bandana = Materials.matte(UIColor(red: 0.42, green: 0.74, blue: 0.36, alpha: 1), roughness: 0.9)

        root.addChild(body)
        for (x, z, phase) in [(-0.075, 0.085, 0), (0.075, 0.085, Float.pi), (-0.075, -0.085, .pi), (0.075, -0.085, 0)] as [(Float, Float, Float)] {
            let pivot = Entity()
            pivot.position = [x, 0.13, z]
            pivot.addSphere(cream, at: [0, -0.05, 0], radius: 1, squash: [0.045, 0.065, 0.045])
            pivot.addSphere(sock, at: [0, -0.1, 0.012], radius: 1, squash: [0.042, 0.03, 0.052])
            root.addChild(pivot)
            legs.append((pivot, phase))
        }

        body.addSphere(cream, at: [0, 0.2, 0], radius: 1, squash: [0.13, 0.115, 0.17])
        body.addSphere(tan, at: [0.035, 0.27, -0.05], radius: 1, squash: [0.085, 0.06, 0.1])
        // Bandana: a knot around the neck and a little point under the chin.
        body.addPart(Meshes.torus(radius: 0.085, tube: 0.022), bandana, at: [0, 0.27, 0.1], scale: .one,
                     rotation: simd_quatf(angle: 0.5, axis: [1, 0, 0]))
        body.addPart(Meshes.cone, bandana, at: [0, 0.22, 0.155], scale: [0.05, 0.07, 0.025],
                     rotation: simd_quatf(angle: .pi + 0.3, axis: [1, 0, 0]))

        head.position = [0, 0.3, 0.13]
        body.addChild(head)
        head.addSphere(cream, at: [0, 0.07, 0.03], radius: 1, squash: [0.15, 0.138, 0.142])
        head.addSphere(sock, at: [0, 0.02, 0.16], radius: 1, squash: [0.075, 0.058, 0.07]) // muzzle
        head.addSphere(nose, at: [0, 0.05, 0.226], radius: 0.026, squash: [1.2, 0.85, 0.8])
        head.addSphere(Materials.matte(UIColor(red: 0.98, green: 0.52, blue: 0.58, alpha: 1)), at: [0, -0.02, 0.2],
                       radius: 0.02, squash: [1, 0.5, 0.7]) // tongue
        ActorModels.addCuteEyes(to: head, at: [0, 0.095, 0.155], spacing: 0.12, size: 0.038)
        for side: Float in [-1, 1] {
            let pivot = Entity()
            pivot.position = [side * 0.105, 0.16, 0.015]
            pivot.addSphere(tan, at: [side * 0.018, -0.07, 0], radius: 1, squash: [0.034, 0.095, 0.065])
            head.addChild(pivot)
            ears.append((pivot, side))
        }

        tail.position = [0, 0.25, -0.16]
        tail.addSphere(tan, at: [0, 0, -0.06], radius: 1, squash: [0.03, 0.03, 0.07])
        tail.addSphere(sock, at: [0, 0, -0.125], radius: 0.032)
        body.addChild(tail)
    }
}

extension ActorModels {
    /// The pet keeper: a round, knobbly black truffle cap, a green apron with a paw print, and a bowl of kibble.
    static func buildTruffle(into e: Entity) {
        e.addCylinder(Materials.matte(Palette.stem), at: [0, 0.55, 0], radius: 0.3, height: 0.9)
        let apron = Materials.matte(UIColor(red: 0.42, green: 0.66, blue: 0.4, alpha: 1), roughness: 0.9)
        e.addCylinder(apron, at: [0, 0.48, 0.04], radius: 0.31, height: 0.6)
        let paw = Materials.matte(UIColor(red: 0.97, green: 0.92, blue: 0.78, alpha: 1))
        e.addSphere(paw, at: [0, 0.5, 0.34], radius: 1, squash: [0.06, 0.05, 0.02])
        for (x, y) in [(-0.065, 0.575), (-0.022, 0.6), (0.022, 0.6), (0.065, 0.575)] as [(Float, Float)] {
            e.addSphere(paw, at: [x, y, 0.33], radius: 1, squash: [0.022, 0.022, 0.014])
        }
        e.addSphere(Materials.matte(Palette.skin), at: [0, 1.18, 0], radius: 0.25)
        let eye = Materials.glossy(Palette.eye)
        e.addSphere(eye, at: [-0.08, 1.21, 0.22], radius: 0.035)
        e.addSphere(eye, at: [0.08, 1.21, 0.22], radius: 0.035)
        e.addSphere(Materials.matte(Palette.blush, roughness: 1), at: [-0.14, 1.13, 0.18], radius: 0.04, squash: [1, 0.6, 0.4])
        e.addSphere(Materials.matte(Palette.blush, roughness: 1), at: [0.14, 1.13, 0.18], radius: 0.04, squash: [1, 0.6, 0.4])

        // A truffle: round, dark, knobbly, with pale marbling peeking through.
        let cap = Materials.matte(UIColor(red: 0.25, green: 0.17, blue: 0.13, alpha: 1), roughness: 1)
        let capCenter: SIMD3<Float> = [0, 1.52, 0], capRadii: SIMD3<Float> = [0.44, 0.34, 0.44]
        e.addSphere(cap, at: capCenter, radius: 1, squash: capRadii)
        for direction in fibonacciDirections(30) where direction.y > -0.25 {
            e.addSphere(cap, at: surface(capCenter, capRadii, direction), radius: 0.075)
        }
        let marble = Materials.matte(UIColor(red: 0.78, green: 0.66, blue: 0.56, alpha: 1))
        for direction in fibonacciDirections(9) where direction.y > 0 {
            e.addSphere(marble, at: surface(capCenter, capRadii, direction) + direction * 0.03, radius: 0.03, squash: [1.6, 0.5, 0.9])
        }

        // A bowl of kibble, held out in both hands.
        let skin = Materials.matte(Palette.skin)
        let bowl = Materials.glossy(UIColor(red: 0.85, green: 0.3, blue: 0.25, alpha: 1))
        e.addCylinder(bowl, at: [0, 0.8, 0.4], radius: 0.15, height: 0.08)
        let kibble = Materials.matte(UIColor(red: 0.72, green: 0.45, blue: 0.24, alpha: 1))
        for (x, z) in [(-0.06, 0.37), (0.05, 0.42), (0, 0.46), (0.07, 0.35), (-0.03, 0.41)] as [(Float, Float)] {
            e.addSphere(kibble, at: [x, 0.855, z], radius: 0.035)
        }
        for side: Float in [-1, 1] {
            e.addSphere(skin, at: [side * 0.17, 0.8, 0.34], radius: 0.07)
        }
    }
}
