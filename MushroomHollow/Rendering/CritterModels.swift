import RealityKit
import UIKit

/// Placeholder models for the second species of the inner zones and the outer ring's critters.
/// Like `ActorModels`: primitives only, facing +Z, standing on y = 0. Every one gets big anime eyes.
@MainActor
extension ActorModels {
    // MARK: - Inner ring

    static func buildLadybug(into e: Entity) {
        let shell = Materials.glossy(Palette.ladybugRed)
        let black = Materials.glossy(Palette.bugBlack)
        let center: SIMD3<Float> = [0, 0.3, -0.05], radii: SIMD3<Float> = [0.42, 0.3, 0.48]
        e.addSphere(shell, at: center, radius: 1, squash: radii)
        let spots: [SIMD3<Float>] = [[0, 1, 0.55], [0.55, 0.8, 0.3], [-0.55, 0.8, 0.3], [0.6, 0.7, -0.45],
                                     [-0.6, 0.7, -0.45], [0.25, 0.9, -0.15], [-0.25, 0.9, -0.15]]
        for direction in spots {
            e.addSphere(black, at: surface(center, radii, direction), radius: 0.075, squash: [1, 0.6, 1])
        }
        e.addSphere(black, at: [0, 0.26, 0.42], radius: 0.2)
        addCuteEyes(to: e, at: [0, 0.3, 0.55], spacing: 0.17, size: 0.075)
        addAntennae(to: e, from: [0, 0.4, 0.5], spread: 0.14, length: 0.26, material: black)
        addLegs(to: e, material: black, zs: [-0.2, 0.05, 0.28], hipX: 0.3, hipY: 0.18, reach: 0.18)
    }

    static func buildPillBug(into e: Entity) {
        let light = Materials.matte(Palette.pillGrey, roughness: 0.5)
        let dark = Materials.matte(Palette.pillDark, roughness: 0.5)
        for i in 0..<6 {
            let z = 0.32 - Float(i) * 0.13
            let r: Float = 0.3 - abs(Float(i) - 2) * 0.025
            e.addSphere(i % 2 == 0 ? light : dark, at: [0, 0.26, z], radius: r, squash: [1, 0.85, 0.55])
        }
        e.addSphere(dark, at: [0, 0.2, 0.46], radius: 0.18)
        addCuteEyes(to: e, at: [0, 0.24, 0.58], spacing: 0.14, size: 0.06)
        addAntennae(to: e, from: [0, 0.3, 0.55], spread: 0.18, length: 0.3, material: dark)
        addLegs(to: e, material: dark, zs: [-0.25, -0.05, 0.15, 0.32], hipX: 0.22, hipY: 0.1, reach: 0.12)
    }

    static func buildAcornling(into e: Entity) {
        let nut = Materials.matte(Palette.acornBrown, roughness: 0.4)
        let cap = Materials.matte(Palette.acornCap, roughness: 1)
        e.addPart(Meshes.teardrop, nut, at: [0, 0.45, 0], scale: [0.36, 0.4, 0.36])
        e.addSphere(cap, at: [0, 0.72, 0], radius: 0.4, squash: [1, 0.5, 1])
        let rim = Materials.matte(Palette.acornCapDark, roughness: 1)
        for i in 0..<10 {
            let a = Float(i) / 10 * 2 * .pi
            e.addSphere(rim, at: [sin(a) * 0.36, 0.68, cos(a) * 0.36], radius: 0.07)
        }
        e.addCylinder(cap, at: [0, 0.95, 0], radius: 0.04, height: 0.14)
        e.addPart(Meshes.teardrop, Materials.matte(Palette.leaf), at: [0.1, 1.04, 0], scale: [0.08, 0.16, 0.02],
                  rotation: simd_quatf(angle: -0.8, axis: [0, 0, 1]))
        addCuteEyes(to: e, at: [0, 0.45, 0.31], spacing: 0.18, size: 0.08)
        for side: Float in [-1, 1] {
            e.addSphere(cap, at: [side * 0.14, 0.05, 0.05], radius: 0.09, squash: [1, 0.6, 1.3]) // feet
            e.addSphere(nut, at: [side * 0.36, 0.38, 0.05], radius: 0.07) // stubby arms
        }
    }

    static func buildBogFrog(into e: Entity) {
        let skin = Materials.matte(Palette.frogGreen, roughness: 0.35)
        let belly = Materials.matte(Palette.frogBelly, roughness: 0.6)
        e.addSphere(skin, at: [0, 0.38, -0.05], radius: 0.5, squash: [1.1, 0.72, 1])
        e.addSphere(belly, at: [0, 0.3, 0.16], radius: 0.38, squash: [1, 0.7, 0.8])
        for side: Float in [-1, 1] {
            e.addSphere(skin, at: [side * 0.22, 0.64, 0.2], radius: 0.17) // eye bumps
            e.addSphere(skin, at: [side * 0.45, 0.2, -0.2], radius: 0.25, squash: [0.8, 0.7, 1.3]) // haunches
            e.addSphere(skin, at: [side * 0.5, 0.03, 0.08], radius: 0.14, squash: [1.2, 0.3, 1.5])
            e.addSphere(skin, at: [side * 0.25, 0.04, 0.36], radius: 0.1, squash: [1.2, 0.4, 1.2])
        }
        addCuteEyes(to: e, at: [0, 0.67, 0.3], spacing: 0.44, size: 0.12)
        e.addSphere(Materials.matte(Palette.bugBlack), at: [0, 0.36, 0.4], radius: 1, squash: [0.2, 0.012, 0.04]) // smile
        // A lily pad hat with a bud on it.
        e.addCylinder(Materials.matte(Palette.moss), at: [0, 0.66, -0.2], radius: 0.2, height: 0.02)
        e.addSphere(Materials.matte(Palette.rosePink), at: [0, 0.71, -0.2], radius: 0.06, squash: [1, 1.3, 1])
    }

    /// A plump, pear-shaped green aphid with a glistening drop of honeydew on its back.
    static func buildAphid(into e: Entity) {
        let green = Materials.matte(UIColor(red: 0.55, green: 0.85, blue: 0.35, alpha: 1), roughness: 0.4)
        let pale = Materials.matte(UIColor(red: 0.78, green: 0.95, blue: 0.55, alpha: 1), roughness: 0.5)
        let dark = Materials.matte(UIColor(red: 0.25, green: 0.45, blue: 0.15, alpha: 1))
        e.addSphere(green, at: [0, 0.32, -0.08], radius: 1, squash: [0.34, 0.3, 0.42])
        e.addSphere(pale, at: [0, 0.24, 0.02], radius: 1, squash: [0.28, 0.2, 0.34])
        e.addSphere(green, at: [0, 0.34, 0.32], radius: 0.2)
        for side: Float in [-1, 1] {
            // The two little "tailpipes" aphids have on their backs.
            e.addRod(dark, from: [side * 0.12, 0.45, -0.3], to: [side * 0.16, 0.56, -0.42], radius: 0.025)
        }
        e.addSphere(Materials.translucent(UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1), opacity: 0.8), at: [0, 0.64, -0.12],
                    radius: 0.09, squash: [1, 1.2, 1])
        addCuteEyes(to: e, at: [0, 0.38, 0.49], spacing: 0.15, size: 0.07)
        addAntennae(to: e, from: [0, 0.48, 0.4], spread: 0.12, length: 0.34, material: dark)
        addLegs(to: e, material: dark, zs: [-0.22, 0, 0.2], hipX: 0.22, hipY: 0.2, reach: 0.16)
    }

    /// A pink earthworm in a lazy S, with a pale saddle band. It dives underground when hurt.
    static func buildEarthworm(into e: Entity) {
        let pink = Materials.matte(UIColor(red: 0.93, green: 0.58, blue: 0.6, alpha: 1), roughness: 0.35)
        let band = Materials.matte(UIColor(red: 0.98, green: 0.78, blue: 0.72, alpha: 1), roughness: 0.4)
        let segments = 9
        for i in 0..<segments {
            let t = Float(i) / Float(segments - 1)
            let z = 0.55 - t * 1.25
            let x = sin(t * 5) * 0.14
            // The head end rears up a little.
            let y = 0.17 + max(0, 0.35 - t) * 0.6
            let r: Float = 0.17 - abs(t - 0.35) * 0.08
            e.addSphere(i == 3 ? band : pink, at: [x, y, z], radius: r)
        }
        addCuteEyes(to: e, at: [sin(0) * 0.14, 0.4, 0.68], spacing: 0.12, size: 0.055)
        e.addSphere(Materials.matte(UIColor(red: 0.55, green: 0.25, blue: 0.3, alpha: 1)), at: [0, 0.32, 0.7], radius: 1,
                    squash: [0.05, 0.015, 0.02]) // mouth
    }

    /// A glossy brown cricket with long, folded hind legs and whip antennae.
    static func buildCricket(into e: Entity) {
        let shell = Materials.glossy(UIColor(red: 0.42, green: 0.28, blue: 0.16, alpha: 1))
        let dark = Materials.glossy(UIColor(red: 0.2, green: 0.13, blue: 0.08, alpha: 1))
        let belly = Materials.matte(UIColor(red: 0.72, green: 0.55, blue: 0.32, alpha: 1))
        e.addSphere(shell, at: [0, 0.42, -0.12], radius: 1, squash: [0.28, 0.24, 0.52])
        e.addSphere(belly, at: [0, 0.34, -0.1], radius: 1, squash: [0.22, 0.18, 0.44])
        e.addSphere(dark, at: [0, 0.5, -0.2], radius: 1, squash: [0.3, 0.14, 0.46]) // folded wings
        e.addSphere(shell, at: [0, 0.48, 0.38], radius: 0.22)
        addCuteEyes(to: e, at: [0, 0.52, 0.56], spacing: 0.18, size: 0.075)
        for side: Float in [-1, 1] {
            e.addRod(dark, from: [side * 0.06, 0.64, 0.5], to: [side * 0.32, 1.05, 0.2], radius: 0.012)
            e.addRod(dark, from: [side * 0.32, 1.05, 0.2], to: [side * 0.5, 1.1, -0.35], radius: 0.01)
            // Big jumping legs: thigh up and back, shin down to the ground.
            e.addRod(shell, from: [side * 0.2, 0.4, -0.05], to: [side * 0.34, 0.78, -0.45], radius: 0.05)
            e.addRod(dark, from: [side * 0.34, 0.78, -0.45], to: [side * 0.3, 0.02, -0.6], radius: 0.025)
            for z: Float in [0.1, 0.3] {
                e.addRod(dark, from: [side * 0.16, 0.32, z], to: [side * 0.3, 0.01, z + 0.08], radius: 0.02)
            }
        }
    }

    // MARK: - Buttercup Meadow

    static func buildFuzzbee(into e: Entity) {
        let fuzz = Materials.matte(Palette.beeYellow, roughness: 1)
        let black = Materials.matte(Palette.bugBlack, roughness: 1)
        e.addSphere(fuzz, at: [0, 1, -0.1], radius: 1, squash: [0.38, 0.36, 0.44])
        let ringUp = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        e.addPart(Meshes.torus(radius: 0.36, tube: 0.05), black, at: [0, 1, -0.16], scale: .one, rotation: ringUp)
        e.addPart(Meshes.torus(radius: 0.28, tube: 0.05), black, at: [0, 1, -0.37], scale: .one, rotation: ringUp)
        e.addPart(Meshes.cone, black, at: [0, 1, -0.58], scale: [0.07, 0.18, 0.07], rotation: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]))
        e.addSphere(Materials.matte(Palette.puffWhite, roughness: 1), at: [0, 1, 0.18], radius: 0.3, squash: [1, 1, 0.5]) // collar
        e.addSphere(fuzz, at: [0, 1.05, 0.36], radius: 0.26)
        addCuteEyes(to: e, at: [0, 1.08, 0.56], spacing: 0.2, size: 0.085)
        addAntennae(to: e, from: [0, 1.26, 0.44], spread: 0.18, length: 0.3, material: black)
        for side: Float in [-1, 1] {
            for z: Float in [-0.1, 0.1] {
                e.addRod(black, from: [side * 0.12, 0.7, z], to: [side * 0.18, 0.5, z + 0.05], radius: 0.02)
            }
        }
        addWings(to: e, pivotY: 1.3, pivotX: 0.18, pivotZ: -0.05, color: Palette.wingGlass,
                 fore: ([0.3, 0.1, -0.02], [0.32, 0.04, 0.17]), hind: ([0.22, 0.05, -0.2], [0.2, 0.03, 0.12]))
    }

    static func buildPuffweed(into e: Entity) {
        let green = Materials.matte(Palette.leaf, roughness: 0.7)
        addRosette(to: e, material: green, count: 5, length: 0.45, width: 0.14)
        e.addRod(Materials.matte(Palette.dandelionStem), from: [0, 0, 0], to: [0, 1.2, 0], radius: 0.07)
        for side: Float in [-1, 1] {
            e.addPart(Meshes.teardrop, green, at: [side * 0.2, 0.62, 0], scale: [0.07, 0.18, 0.03],
                      rotation: simd_quatf(angle: side * -1.1, axis: [0, 0, 1]))
        }
        addFluffball(to: e, center: [0, 1.45, 0], radius: 0.5, tufts: 16)
        addCuteEyes(to: e, at: [0, 1.46, 0.44], spacing: 0.24, size: 0.1)
    }

    static func buildPuffling(into e: Entity) {
        addFluffball(to: e, center: [0, 0.8, 0], radius: 0.28, tufts: 9)
        e.addRod(Materials.matte(Palette.dandelionStem), from: [0, 0.54, 0], to: [0, 0.26, 0], radius: 0.015)
        e.addSphere(Materials.matte(Palette.acornBrown), at: [0, 0.22, 0], radius: 0.05, squash: [0.6, 1.4, 0.6])
        addCuteEyes(to: e, at: [0, 0.82, 0.24], spacing: 0.14, size: 0.06)
    }

    // MARK: - Mossback Creek

    static func buildMossTurtle(into e: Entity) {
        let shell = Materials.matte(Palette.turtleShell, roughness: 0.7)
        let skin = Materials.matte(Palette.turtleSkin, roughness: 0.6)
        let center: SIMD3<Float> = [0, 0.4, -0.05], radii: SIMD3<Float> = [0.8, 0.55, 0.95]
        e.addSphere(shell, at: center, radius: 1, squash: radii)
        e.addPart(Meshes.torus(radius: 0.8, tube: 0.08), Materials.matte(Palette.turtleShellDark), at: [0, 0.38, -0.05],
                  scale: [1, 1, 1.18])
        let scute = Materials.matte(Palette.turtleShellDark, roughness: 0.8)
        for direction: SIMD3<Float> in [[0.5, 0.75, 0.3], [-0.5, 0.75, 0.3], [0.5, 0.75, -0.5], [-0.5, 0.75, -0.5], [0, 0.8, -0.8], [0, 0.85, 0.6]] {
            e.addSphere(scute, at: surface(center, radii, direction), radius: 0.16, squash: [1, 0.35, 1])
        }
        // A little garden on its back: moss and a tiny toadstool.
        let moss = Materials.matte(Palette.moss, roughness: 1)
        e.addSphere(moss, at: [0.1, 0.92, -0.1], radius: 0.4, squash: [1, 0.3, 1.1])
        e.addSphere(moss, at: [-0.25, 0.88, 0.2], radius: 0.22, squash: [1, 0.35, 1])
        e.addCylinder(Materials.matte(Palette.stem), at: [0.05, 1.08, -0.1], radius: 0.035, height: 0.2)
        e.addSphere(Materials.matte(Palette.capRed, roughness: 0.5), at: [0.05, 1.18, -0.1], radius: 0.1, squash: [1, 0.55, 1])
        e.addSphere(skin, at: [0, 0.45, 0.95], radius: 0.28)
        addCuteEyes(to: e, at: [0, 0.52, 1.17], spacing: 0.2, size: 0.085)
        for side: Float in [-1, 1] {
            for z: Float in [-0.5, 0.45] {
                e.addCylinder(skin, at: [side * 0.55, 0.14, z], radius: 0.16, height: 0.28)
            }
        }
        e.addPart(Meshes.cone, skin, at: [0, 0.25, -1.05], scale: [0.1, 0.25, 0.1], rotation: simd_quatf(angle: -1.8, axis: [1, 0, 0]))
    }

    static func buildEmberNewt(into e: Entity) {
        let skin = Materials.matte(Palette.newtOrange, roughness: 0.3)
        e.addSphere(skin, at: [0, 0.25, 0], radius: 1, squash: [0.25, 0.2, 0.45])
        for (z, r) in [(Float(-0.5), Float(0.15)), (-0.72, 0.11), (-0.9, 0.07)] {
            e.addSphere(skin, at: [0, 0.1 + r * 0.6, z], radius: r, squash: [1, 0.8, 1.4])
        }
        e.addSphere(skin, at: [0, 0.3, 0.5], radius: 0.24, squash: [1.1, 0.85, 1])
        addCuteEyes(to: e, at: [0, 0.38, 0.66], spacing: 0.22, size: 0.08)
        let glow = Materials.glow(Palette.emberGlow)
        for (i, z) in [Float(0.25), 0.05, -0.15, -0.35].enumerated() {
            e.addSphere(glow, at: [(i % 2 == 0 ? 0.07 : -0.07), 0.43 - abs(z) * 0.12, z], radius: 0.05)
        }
        // Axolotl frills either side of the head.
        for side: Float in [-1, 1] {
            for i in 0..<3 {
                let tilt = Float(i - 1) * 0.5
                e.addPart(Meshes.teardrop, glow, at: [side * 0.27, 0.4 + Float(i - 1) * 0.06, 0.42], scale: [0.03, 0.09, 0.03],
                          rotation: simd_quatf(angle: side * (-1.1 + tilt), axis: [0, 0, 1]))
            }
            for z: Float in [-0.22, 0.22] {
                e.addSphere(skin, at: [side * 0.28, 0.07, z], radius: 0.09, squash: [1.4, 0.5, 1])
            }
        }
    }

    // MARK: - Silkshade Thicket

    static func buildWeaverSpider(into e: Entity) {
        let body = Materials.matte(Palette.spiderPurple, roughness: 0.6)
        let dark = Materials.matte(Palette.spiderDark, roughness: 0.6)
        let center: SIMD3<Float> = [0, 0.65, -0.35], radii: SIMD3<Float> = [0.45, 0.4, 0.5]
        e.addSphere(body, at: center, radius: 1, squash: radii)
        let glow = Materials.glow(Palette.spiderGlow)
        for direction: SIMD3<Float> in [[0, 1, 0.1], [0.25, 0.9, -0.4], [-0.25, 0.9, -0.4]] {
            e.addSphere(glow, at: surface(center, radii, direction), radius: 0.06)
        }
        e.addSphere(dark, at: [0, 0.48, 0.2], radius: 0.3)
        addCuteEyes(to: e, at: [0, 0.54, 0.44], spacing: 0.2, size: 0.08)
        let beady = Materials.glossy(Palette.bugBlack)
        for side: Float in [-1, 1] {
            e.addSphere(beady, at: [side * 0.06, 0.7, 0.4], radius: 0.035)
            e.addPart(Meshes.cone, Materials.matte(Palette.capSpot), at: [side * 0.06, 0.3, 0.45], scale: [0.03, 0.09, 0.03],
                      rotation: simd_quatf(angle: .pi, axis: [1, 0, 0]))
            for (i, zDir) in [Float(0.8), 0.25, -0.25, -0.7].enumerated() {
                let hip = SIMD3<Float>(side * 0.2, 0.5, 0.22 - Float(i) * 0.08)
                let out = simd_normalize(SIMD3<Float>(side, 0, zDir))
                let knee = hip + out * 0.45 + [0, 0.35, 0]
                var foot = hip + out * 0.95
                foot.y = 0.02
                e.addRod(dark, from: hip, to: knee, radius: 0.04)
                e.addRod(dark, from: knee, to: foot, radius: 0.03)
            }
        }
    }

    static func buildDuskMoth(into e: Entity) {
        let fur = Materials.matte(Palette.mothFur, roughness: 1)
        let lilac = Materials.matte(Palette.mothLilac, roughness: 1)
        e.addSphere(fur, at: [0, 1.2, -0.12], radius: 1, squash: [0.25, 0.25, 0.5])
        e.addSphere(fur, at: [0, 1.25, 0.25], radius: 0.28)
        e.addSphere(lilac, at: [0, 1.28, 0.45], radius: 0.22)
        addCuteEyes(to: e, at: [0, 1.3, 0.62], spacing: 0.18, size: 0.075)
        // Feathery antennae.
        for side: Float in [-1, 1] {
            let base = SIMD3<Float>(side * 0.06, 1.45, 0.5), tip = SIMD3<Float>(side * 0.25, 1.75, 0.62)
            e.addRod(lilac, from: base, to: tip, radius: 0.015)
            for step in 1...3 {
                e.addSphere(fur, at: base + (tip - base) * (Float(step) / 3.5), radius: 0.06, squash: [1, 0.3, 0.6])
            }
        }
        addWings(to: e, pivotY: 1.35, pivotX: 0.15, pivotZ: 0, color: Palette.mothLilac,
                 fore: ([0.55, 0.05, 0.1], [0.55, 0.04, 0.38]), hind: ([0.45, -0.05, -0.35], [0.4, 0.04, 0.3]),
                 eyespot: Palette.spiderGlow)
    }

    // MARK: - Pinecone Rise

    static func buildHedgehog(into e: Entity) {
        let fur = Materials.matte(Palette.hedgehogBrown, roughness: 1)
        let face = Materials.matte(Palette.hedgehogFace, roughness: 0.9)
        let center: SIMD3<Float> = [0, 0.42, -0.05], radii: SIMD3<Float> = [0.55, 0.45, 0.62]
        e.addSphere(fur, at: center, radius: 1, squash: radii)
        let quill = Materials.matte(Palette.quill, roughness: 0.8)
        for direction in fibonacciDirections(40) where direction.y > -0.05 && direction.z < 0.5 {
            e.addPart(Meshes.cone, quill, at: surface(center, radii, direction) + direction * 0.08, scale: [0.06, 0.28, 0.06],
                      rotation: simd_quatf(from: [0, 1, 0], to: direction))
        }
        e.addSphere(face, at: [0, 0.36, 0.45], radius: 0.28, squash: [1, 0.9, 1.1])
        e.addSphere(face, at: [0, 0.32, 0.72], radius: 0.1)
        e.addSphere(Materials.glossy(Palette.bugBlack), at: [0, 0.34, 0.8], radius: 0.045)
        addCuteEyes(to: e, at: [0, 0.44, 0.64], spacing: 0.2, size: 0.07)
        for side: Float in [-1, 1] {
            e.addSphere(face, at: [side * 0.2, 0.62, 0.38], radius: 0.07)
            for z: Float in [-0.3, 0.3] {
                e.addSphere(face, at: [side * 0.3, 0.05, z], radius: 0.08, squash: [1, 0.6, 1.3])
            }
        }
    }

    static func buildConeKnight(into e: Entity) {
        let light = Materials.matte(Palette.pinecone, roughness: 0.9)
        let dark = Materials.matte(Palette.pineconeDark, roughness: 0.9)
        e.addSphere(dark, at: [0, 0.85, 0], radius: 1, squash: [0.42, 0.62, 0.42])
        let rings: [Float] = [0.3, 0.44, 0.48, 0.46, 0.38, 0.24]
        for (layer, ringRadius) in rings.enumerated() {
            let count = 7
            for j in 0..<count {
                let a = Float(j) / Float(count) * 2 * .pi + Float(layer) * 0.35
                let facingFront = abs(atan2(sin(a), cos(a))) < 0.55
                if facingFront, (2...4).contains(layer) { continue } // leave the face clear
                e.addSphere(layer % 2 == 0 ? light : dark, at: [sin(a) * ringRadius, 0.35 + Float(layer) * 0.2, cos(a) * ringRadius],
                            radius: 0.19, squash: [1, 0.55, 0.75])
            }
        }
        e.addSphere(Materials.matte(Palette.hedgehogFace), at: [0, 0.9, 0.34], radius: 1, squash: [0.22, 0.22, 0.1])
        addCuteEyes(to: e, at: [0, 0.92, 0.42], spacing: 0.15, size: 0.055)
        // An acorn-cap helmet and a twig spear.
        e.addSphere(Materials.matte(Palette.acornCap, roughness: 1), at: [0, 1.52, 0], radius: 0.3, squash: [1, 0.55, 1])
        e.addCylinder(Materials.matte(Palette.acornCap), at: [0, 1.7, 0], radius: 0.03, height: 0.12)
        e.addRod(Materials.matte(Palette.bark), from: [0.5, 0.1, 0.25], to: [0.5, 1.6, 0.35], radius: 0.03)
        e.addPart(Meshes.cone, Materials.glossy(UIColor(white: 0.6, alpha: 1)), at: [0.5, 1.7, 0.36], scale: [0.06, 0.2, 0.06])
        e.addSphere(dark, at: [0.45, 0.8, 0.3], radius: 0.08)
        for side: Float in [-1, 1] {
            e.addCylinder(dark, at: [side * 0.15, 0.1, 0], radius: 0.08, height: 0.2)
        }
    }

    // MARK: - Briar Tangle

    static func buildMantis(into e: Entity) {
        let pink = Materials.matte(Palette.mantisPink, roughness: 0.6)
        let white = Materials.matte(Palette.mantisWhite, roughness: 0.6)
        e.addSphere(pink, at: [0, 0.55, -0.4], radius: 1, squash: [0.22, 0.2, 0.42])
        e.addRod(white, from: [0, 0.5, -0.05], to: [0, 1.15, 0.25], radius: 0.08)
        e.addSphere(white, at: [0, 1.28, 0.3], radius: 1, squash: [0.2, 0.15, 0.14])
        addCuteEyes(to: e, at: [0, 1.32, 0.38], spacing: 0.3, size: 0.085)
        addAntennae(to: e, from: [0, 1.4, 0.35], spread: 0.2, length: 0.35, material: white)
        for side: Float in [-1, 1] {
            // Folded raptor arms with petal lobes.
            let shoulder = SIMD3<Float>(side * 0.08, 1.05, 0.25), elbow = SIMD3<Float>(side * 0.13, 1.25, 0.55)
            e.addRod(pink, from: shoulder, to: elbow, radius: 0.035)
            e.addRod(white, from: elbow, to: [side * 0.13, 0.95, 0.62], radius: 0.03)
            e.addPart(Meshes.teardrop, pink, at: (shoulder + elbow) / 2 + [side * 0.05, 0, 0], scale: [0.08, 0.12, 0.03],
                      rotation: simd_quatf(angle: side * -0.6, axis: [0, 0, 1]))
            for z: Float in [-0.15, -0.45] {
                let hip = SIMD3<Float>(side * 0.06, 0.55, z)
                let knee = hip + [side * 0.3, 0.1, 0.05]
                e.addRod(pink, from: hip, to: knee, radius: 0.025)
                e.addRod(pink, from: knee, to: [side * 0.45, 0, z + 0.1], radius: 0.02)
                e.addPart(Meshes.teardrop, pink, at: knee, scale: [0.07, 0.1, 0.02], rotation: simd_quatf(angle: side * -1.2, axis: [0, 0, 1]))
            }
        }
    }

    static func buildThornrose(into e: Entity) {
        let leaf = Materials.matte(Palette.leaf, roughness: 0.7)
        let stem = Materials.matte(Palette.thornStem, roughness: 0.7)
        addRosette(to: e, material: leaf, count: 4, length: 0.5, width: 0.16)
        e.addRod(stem, from: [0, 0, 0], to: [0, 1.3, 0], radius: 0.1)
        let thorn = Materials.matte(Palette.roseDark, roughness: 0.6)
        for i in 0..<6 {
            let a = Float(i) * 2.2
            let out = SIMD3<Float>(sin(a), 0.3, cos(a))
            e.addPart(Meshes.cone, thorn, at: [sin(a) * 0.12, 0.25 + Float(i) * 0.17, cos(a) * 0.12], scale: [0.04, 0.12, 0.04],
                      rotation: simd_quatf(from: [0, 1, 0], to: simd_normalize(out)))
        }
        for side: Float in [-1, 1] {
            e.addRod(stem, from: [0, 0.8, 0], to: [side * 0.45, 1.0, 0.15], radius: 0.05)
            e.addPart(Meshes.teardrop, leaf, at: [side * 0.55, 1.05, 0.18], scale: [0.08, 0.15, 0.03],
                      rotation: simd_quatf(angle: side * -1.2, axis: [0, 0, 1]))
        }
        // The blossom faces forward, with two rings of petals around a face.
        let head = SIMD3<Float>(0, 1.6, 0)
        e.addSphere(Materials.matte(Palette.roseRed, roughness: 0.6), at: head, radius: 0.4)
        for (ring, (color, radius, z)) in [(Palette.roseRed, Float(0.42), Float(-0.05)), (Palette.rosePink, 0.3, 0.12)].enumerated() {
            let petal = Materials.matte(color, roughness: 0.6)
            for i in 0..<8 {
                let a = (Float(i) + Float(ring) * 0.5) / 8 * 2 * .pi
                e.addPart(Meshes.teardrop, petal, at: head + [sin(a) * radius, cos(a) * radius, z], scale: [0.2, 0.26, 0.07],
                          rotation: simd_quatf(angle: -a, axis: [0, 0, 1]))
            }
        }
        addCuteEyes(to: e, at: head + [0, 0.04, 0.36], spacing: 0.2, size: 0.08)
    }

    // MARK: - Stagshade Grove

    static func buildGrumblecap(into e: Entity) {
        let stem = Materials.matte(Palette.stem)
        e.addCylinder(stem, at: [0, 0.65, 0], radius: 0.55, height: 1.1)
        e.addSphere(stem, at: [0, 0.25, 0], radius: 0.58, squash: [1, 0.5, 1])
        addCuteEyes(to: e, at: [0, 0.95, 0.5], spacing: 0.3, size: 0.11, blush: false)
        let dark = Materials.matte(Palette.bugBlack)
        for side: Float in [-1, 1] {
            // Grumpy brows, low on the inside.
            e.addPart(Meshes.roundedBox, dark, at: [side * 0.15, 1.13, 0.55], scale: [0.17, 0.035, 0.04],
                      rotation: simd_quatf(angle: side * 0.35, axis: [0, 0, 1]))
            e.addSphere(stem, at: [side * 0.62, 0.6, 0.1], radius: 0.14)
            e.addSphere(stem, at: [side * 0.25, 0.05, 0.15], radius: 0.16, squash: [1, 0.5, 1.3])
        }
        e.addSphere(dark, at: [0, 0.78, 0.56], radius: 1, squash: [0.08, 0.02, 0.03])
        let center: SIMD3<Float> = [0, 1.45, 0], radii: SIMD3<Float> = [1.05, 0.58, 1.05]
        e.addSphere(Materials.matte(Palette.capRed, roughness: 0.55), at: center, radius: 1, squash: radii)
        e.addCylinder(stem, at: [0, 1.43, 0], radius: 1, height: 0.04)
        let spot = Materials.matte(Palette.capSpot)
        for direction in fibonacciDirections(18) where direction.y > 0.25 {
            e.addSphere(spot, at: surface(center, radii, direction), radius: 0.13, squash: [1, 0.45, 1])
        }
    }

    static func buildStagBeetle(into e: Entity) {
        let shell = Materials.glossy(Palette.stagBrown)
        let dark = Materials.glossy(Palette.stagDark)
        e.addSphere(shell, at: [0, 0.55, -0.2], radius: 1, squash: [0.7, 0.42, 0.85])
        e.addSphere(dark, at: [0, 0.55, 0.45], radius: 1, squash: [0.5, 0.32, 0.3])
        e.addSphere(dark, at: [0, 0.5, 0.8], radius: 0.3, squash: [1.2, 0.8, 0.9])
        addCuteEyes(to: e, at: [0, 0.58, 1.03], spacing: 0.3, size: 0.08)
        for side: Float in [-1, 1] {
            // Huge antler-like mandibles.
            let base = SIMD3<Float>(side * 0.2, 0.5, 0.95), bend = SIMD3<Float>(side * 0.42, 0.62, 1.4)
            let tip = SIMD3<Float>(side * 0.16, 0.68, 1.78)
            e.addRod(shell, from: base, to: bend, radius: 0.07)
            e.addRod(shell, from: bend, to: tip, radius: 0.055)
            e.addPart(Meshes.cone, shell, at: bend + [side * -0.05, 0.1, 0.05], scale: [0.04, 0.16, 0.04])
            for z: Float in [-0.55, -0.1, 0.35] {
                let hip = SIMD3<Float>(side * 0.5, 0.35, z)
                let knee = hip + [side * 0.3, 0.1, 0]
                e.addRod(dark, from: hip, to: knee, radius: 0.045)
                e.addRod(dark, from: knee, to: [side * 0.95, 0, z + 0.1], radius: 0.035)
            }
        }
    }

    // MARK: - The Sunken Warren

    /// A plump velvet mole with a pink star nose and huge digging hands. Delvers wear a miner's hat
    /// and lamp; Moldywarp, the Warren King, is the same shape `size` times bigger, with a crown and cape.
    static func buildMole(into e: Entity, size s: Float, king: Bool) {
        let fur = Materials.matte(king ? Palette.moleKing : Palette.moleFur, roughness: 1)
        let pink = Materials.matte(Palette.molePink, roughness: 0.7)
        let claw = Materials.matte(Palette.claw, roughness: 0.5)
        e.addSphere(fur, at: [0, 0.5 * s, -0.05 * s], radius: 1, squash: SIMD3(0.62, 0.5, 0.75) * s)
        e.addSphere(Materials.matte(Palette.moleBelly, roughness: 1), at: [0, 0.4 * s, 0.3 * s], radius: 1,
                    squash: SIMD3(0.45, 0.36, 0.42) * s)
        // A snout ending in a pink star of feelers.
        e.addSphere(fur, at: [0, 0.46 * s, 0.68 * s], radius: 0.2 * s, squash: [1, 0.85, 1.2])
        e.addSphere(pink, at: [0, 0.46 * s, 0.9 * s], radius: 0.08 * s)
        for i in 0..<8 {
            let a = Float(i) / 8 * 2 * .pi
            e.addSphere(pink, at: [sin(a) * 0.1 * s, (0.46 + cos(a) * 0.1) * s, 0.87 * s], radius: 0.04 * s)
        }
        addCuteEyes(to: e, at: [0, 0.66 * s, 0.6 * s], spacing: 0.32 * s, size: 0.07 * s)
        for side: Float in [-1, 1] {
            // Big pink shovel hands, palms out, with pale claws.
            let hand = SIMD3<Float>(side * 0.55, 0.32, 0.45) * s
            e.addSphere(pink, at: hand, radius: 0.2 * s, squash: [0.5, 1, 0.9])
            for c in 0..<4 {
                e.addPart(Meshes.cone, claw, at: hand + SIMD3(side * 0.03, -0.2, (Float(c) - 1.5) * 0.08) * s,
                          scale: SIMD3(0.03, 0.12, 0.03) * s, rotation: simd_quatf(angle: .pi, axis: [1, 0, 0]))
            }
            e.addSphere(pink, at: SIMD3(side * 0.3, 0.06, -0.45) * s, radius: 0.12 * s, squash: [1, 0.5, 1.3])
        }
        e.addRod(pink, from: SIMD3(0, 0.32, -0.76) * s, to: SIMD3(0, 0.38, -0.98) * s, radius: 0.03 * s)
        if king {
            // A gold crown with a glowing gem, and a red cape down the back.
            let gold = Materials.glossy(Palette.crown)
            e.addCylinder(gold, at: SIMD3(0, 1.0, 0.05) * s, radius: 0.22 * s, height: 0.12 * s)
            for i in 0..<6 {
                let a = Float(i) / 6 * 2 * .pi
                e.addPart(Meshes.cone, gold, at: SIMD3(sin(a) * 0.2, 1.12, 0.05 + cos(a) * 0.2) * s, scale: SIMD3(0.05, 0.14, 0.05) * s)
            }
            e.addSphere(Materials.glow(Palette.roseRed), at: SIMD3(0, 1.0, 0.28) * s, radius: 0.05 * s)
            e.addSphere(Materials.matte(Palette.capeRed, roughness: 0.8), at: SIMD3(0, 0.6, -0.4) * s, radius: 1,
                        squash: SIMD3(0.66, 0.46, 0.42) * s)
        } else {
            // A miner's hat with a lamp: delvers dig by lamplight.
            let hat = Materials.glossy(Palette.minerHat)
            e.addSphere(hat, at: [0, 0.9, 0.12], radius: 0.3, squash: [1, 0.55, 1])
            e.addCylinder(hat, at: [0, 0.88, 0.12], radius: 0.36, height: 0.03)
            e.addSphere(Materials.glow(Palette.lamp), at: [0, 0.98, 0.4], radius: 0.07)
        }
    }

    /// A long, low centipede of glossy red plates, with a leg pair on every segment.
    static func buildRootcrawler(into e: Entity) {
        let shell = Materials.glossy(Palette.crawlerRed)
        let dark = Materials.glossy(Palette.crawlerDark)
        let leg = Materials.matte(Palette.crawlerLeg, roughness: 0.6)
        for i in 0..<8 {
            let z = 0.78 - Float(i) * 0.26
            let r: Float = i == 0 ? 0.3 : 0.27 - Float(i) * 0.012
            let y: Float = i == 0 ? 0.36 : 0.28
            e.addSphere(i % 2 == 0 ? shell : dark, at: [0, y, z], radius: 1, squash: [r * 1.25, r * 0.8, r * 0.75])
            guard i > 0 else { continue }
            for side: Float in [-1, 1] {
                let hip = SIMD3<Float>(side * r, 0.22, z)
                let knee = hip + [side * 0.2, 0.08, 0.02]
                e.addRod(leg, from: hip, to: knee, radius: 0.022)
                e.addRod(leg, from: knee, to: [side * (r + 0.36), 0.01, z + 0.06], radius: 0.018)
            }
        }
        addCuteEyes(to: e, at: [0, 0.44, 1.0], spacing: 0.22, size: 0.07)
        for side: Float in [-1, 1] {
            e.addRod(leg, from: [side * 0.12, 0.26, 1.0], to: [side * 0.06, 0.22, 1.24], radius: 0.03) // mandibles
            e.addRod(dark, from: [side * 0.08, 0.5, 0.96], to: [side * 0.34, 0.8, 1.28], radius: 0.015) // antennae
            e.addRod(dark, from: [side * 0.08, 0.3, -1.05], to: [side * 0.3, 0.45, -1.35], radius: 0.015) // tail feelers
        }
    }

    // MARK: - Shared parts

    /// Big, shiny anime eyes on a face looking along +Z: white, a large iris, and a sparkle, with rosy cheeks.
    static func addCuteEyes(to e: Entity, at center: SIMD3<Float>, spacing: Float, size: Float,
                            iris: UIColor = Palette.eye, blush: Bool = true) {
        let white = Materials.glossy(.white)
        let irisMaterial = Materials.glossy(iris)
        let sparkle = Materials.glow(.white)
        let cheek = Materials.matte(Palette.blush, roughness: 1)
        for side: Float in [-1, 1] {
            let c = center + SIMD3(side * spacing / 2, 0, 0)
            e.addSphere(white, at: c, radius: size, squash: [0.85, 1, 0.5])
            e.addSphere(irisMaterial, at: c + [0, -size * 0.08, size * 0.22], radius: size * 0.72, squash: [0.8, 1, 0.45])
            // Both sparkles on the same side, anime-style.
            e.addSphere(sparkle, at: c + [size * 0.22, size * 0.3, size * 0.5], radius: size * 0.22)
            if blush {
                e.addSphere(cheek, at: c + [side * size * 0.5, -size * 1.25, size * 0.05], radius: size * 0.45, squash: [1, 0.5, 0.3])
            }
        }
    }

    /// A point on an ellipsoid's surface, in `direction` from its center.
    static func surface(_ center: SIMD3<Float>, _ radii: SIMD3<Float>, _ direction: SIMD3<Float>) -> SIMD3<Float> {
        center + radii * simd_normalize(direction)
    }

    /// Evenly spread unit directions (a Fibonacci sphere).
    static func fibonacciDirections(_ count: Int) -> [SIMD3<Float>] {
        (0..<count).map { i in
            let y = 1 - (Float(i) + 0.5) / Float(count) * 2
            let r = (1 - y * y).squareRoot()
            let a = Float(i) * 2.39996
            return [sin(a) * r, y, cos(a) * r]
        }
    }

    private static func addAntennae(to e: Entity, from base: SIMD3<Float>, spread: Float, length: Float,
                                    material: any RealityKit.Material) {
        for side: Float in [-1, 1] {
            let root = base + [side * 0.05, 0, 0]
            let tip = root + [side * spread, length * 0.8, length * 0.4]
            e.addRod(material, from: root, to: tip, radius: 0.012)
            e.addSphere(material, at: tip, radius: 0.03)
        }
    }

    /// Insect legs, one pair per `z`: from the hip out and down to the ground.
    private static func addLegs(to e: Entity, material: any RealityKit.Material, zs: [Float], hipX: Float, hipY: Float, reach: Float) {
        for side: Float in [-1, 1] {
            for z in zs {
                e.addRod(material, from: [side * hipX, hipY, z], to: [side * (hipX + reach), 0.01, z + 0.05], radius: 0.025)
            }
        }
    }

    /// Leaves radiating from the base of a plant.
    private static func addRosette(to e: Entity, material: any RealityKit.Material, count: Int, length: Float, width: Float) {
        for i in 0..<count {
            let a = Float(i) / Float(count) * 2 * .pi + 0.3
            let rotation = simd_quatf(angle: a, axis: [0, 1, 0]) * simd_quatf(angle: 1.2, axis: [1, 0, 0])
            e.addPart(Meshes.teardrop, material, at: [sin(a) * length * 0.8, 0.12, cos(a) * length * 0.8],
                      scale: [width, length, 0.03], rotation: rotation)
        }
    }

    /// A dandelion clock: a white ball with tufts all over.
    private static func addFluffball(to e: Entity, center: SIMD3<Float>, radius: Float, tufts: Int) {
        let fluff = Materials.matte(Palette.puffWhite, roughness: 1)
        e.addSphere(fluff, at: center, radius: radius)
        for direction in fibonacciDirections(tufts) where direction.z < 0.6 {
            e.addSphere(fluff, at: center + direction * radius * 0.95, radius: radius * 0.3)
        }
    }

    /// Two named wing pivots, each with a fore and hind wing (offset and size relative to the pivot).
    private static func addWings(to e: Entity, pivotY: Float, pivotX: Float, pivotZ: Float, color: UIColor,
                                 fore: (SIMD3<Float>, SIMD3<Float>), hind: (SIMD3<Float>, SIMD3<Float>),
                                 eyespot: UIColor? = nil) {
        let material = Materials.translucent(color, opacity: color == Palette.wingGlass ? 0.45 : 0.9)
        for (index, side) in [Float(-1), 1].enumerated() {
            let wing = Entity()
            wing.name = wingNames[index]
            wing.position = [side * pivotX, pivotY, pivotZ]
            let mirror = SIMD3<Float>(side, 1, 1)
            wing.addSphere(material, at: fore.0 * mirror, radius: 1, squash: fore.1)
            wing.addSphere(material, at: hind.0 * mirror, radius: 1, squash: hind.1)
            if let eyespot {
                wing.addSphere(Materials.glow(eyespot), at: fore.0 * mirror + [side * 0.08, 0.03, 0.02], radius: 1,
                               squash: [0.13, 0.02, 0.13])
            }
            e.addChild(wing)
        }
    }
}
