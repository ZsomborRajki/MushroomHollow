import Foundation
import GameCore
import Observation
import RealityKit
import SwiftUI

/// Glue between the world host (simulation), input, camera, and renderer.
/// Driven once per rendered frame by RealityKit's scene update event.
@Observable
final class GameSession {
    // HUD-facing state. Only written when it changes, to keep SwiftUI quiet.
    private(set) var isGamepadConnected = false
    private(set) var debugText = ""

    @ObservationIgnored let host: LocalWorldHost
    @ObservationIgnored let input = InputHub()
    @ObservationIgnored let renderer: WorldRenderer
    @ObservationIgnored private var camera = OrbitCamera()
    @ObservationIgnored private var updateSubscription: EventSubscription?
    @ObservationIgnored private var elapsed: Double = 0
    @ObservationIgnored private var debugRefresh: Double = 0

    init() {
        host = LocalWorldHost()
        renderer = WorldRenderer(map: host.map)
        // Start behind the player, looking at the giant trunk.
        if let player = host.currentSnapshot.entity(host.localPlayerID) {
            camera.yaw = player.yaw + .pi
        }
    }

    func attach(to content: inout RealityViewCameraContent) {
        content.camera = .virtual
        content.add(renderer.root)
        updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.frame(deltaTime: event.deltaTime)
        }
    }

    // MARK: - Touch input from the SwiftUI overlay

    func setTouchMove(_ stick: SIMD2<Float>) { input.touchMove = stick }
    func touchLook(_ translation: CGSize) { input.addTouchLook(translation: translation) }
    func zoom(by meters: Float) { input.addZoom(meters) }

    // MARK: - Frame

    private func frame(deltaTime: TimeInterval) {
        let dt = Float(min(deltaTime, 0.1))
        elapsed += deltaTime

        let frameInput = input.poll(deltaTime: dt)
        camera.apply(look: frameInput.look, zoom: frameInput.zoom)
        host.send(.move(camera.worldDirection(forStick: frameInput.move)))

        host.advance(by: deltaTime)
        renderer.render(host: host, time: elapsed)

        if let player = renderer.renderedPosition(of: host.localPlayerID) {
            camera.follow(player, deltaTime: dt)
        }
        renderer.placeCamera(at: camera.position(avoidingTrunkRadius: host.map.trunkCollisionRadius), lookingAt: camera.focus)

        updateHUD(deltaTime: deltaTime)
    }

    private func updateHUD(deltaTime: TimeInterval) {
        debugRefresh -= deltaTime
        guard debugRefresh <= 0 else { return }
        debugRefresh = 0.25

        let connected = input.isGamepadConnected
        if connected != isGamepadConnected { isGamepadConnected = connected }

        #if DEBUG
        if let p = host.currentSnapshot.entity(host.localPlayerID)?.position {
            let fps = deltaTime > 0 ? Int((1 / deltaTime).rounded()) : 0
            let text = String(format: "tick %llu · %.1f, %.1f · %d fps", host.currentSnapshot.tick, p.x, p.z, fps)
            if text != debugText { debugText = text }
        }
        #endif
    }
}
