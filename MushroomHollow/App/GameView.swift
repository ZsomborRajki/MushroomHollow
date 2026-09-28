import GameCore
import RealityKit
import SwiftUI

struct GameView: View {
    @State private var session = GameSession()
    @State private var lastDrag: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let session = session
        ZStack {
            RealityView { content in
                session.attach(to: &content)
            }
            .ignoresSafeArea()
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { _, size in
                session.setViewportSize(size)
            }
            .gesture(cameraOrbit)
            .simultaneousGesture(cameraZoom)
            .simultaneousGesture(tapToTarget)

            // These read their fast-changing state themselves, so this body doesn't re-run each frame.
            FloatingTextLayer(session: session)
            HapticFeedback(session: session)

            if session.panel == nil {
                if !session.isGamepadConnected {
                    HStack(spacing: 0) {
                        FloatingJoystick { session.setTouchMove($0) }
                            .containerRelativeFrame(.horizontal) { width, _ in width * 0.4 }
                        Spacer(minLength: 0)
                            .allowsHitTesting(false)
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }

                HUDView(session: session)
                gameplayControls(session)
            }

            switch session.panel {
            case .inventory:
                InventoryPanel(session: session)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            case let .npc(npc):
                NPCPanel(session: session, npc: npc)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            case .map:
                MapPanel(session: session)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            case nil:
                EmptyView()
            }

            if session.isFainted {
                FaintedOverlay(glyph: session.glyphs?.primary) {
                    session.perform(.primary)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.isGamepadConnected)
        .animation(.easeInOut(duration: 0.4), value: session.isFainted)
        .animation(.snappy(duration: 0.25), value: session.panel)
        .animation(.snappy, value: session.nearbyNPC)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.saveNow() }
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
    }

    @ViewBuilder
    private func gameplayControls(_ session: GameSession) -> some View {
        if !session.isFainted {
            ActionBar(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .ignoresSafeArea()
                .transition(.opacity)

            UtilityRow(session: session)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if let npc = session.nearbyNPC {
                InteractPrompt(npc: npc, glyph: session.glyphs?.primary) {
                    session.perform(.primary)
                }
                .padding(.bottom, 70)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// One-finger drag on the world orbits the camera.
    private var cameraOrbit: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastDrag.width,
                    height: value.translation.height - lastDrag.height)
                lastDrag = value.translation
                session.touchLook(delta)
            }
            .onEnded { _ in lastDrag = .zero }
    }

    /// Pinch to zoom.
    private var cameraZoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let ratio = value.magnification / lastMagnification
                lastMagnification = value.magnification
                session.zoom(by: Float((1 - ratio) * 12))
            }
            .onEnded { _ in lastMagnification = 1 }
    }

    /// Tap a mob to target it and start auto-attacking; tap an NPC to talk.
    private var tapToTarget: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in session.tapped(value.entity) }
    }
}

/// Utility row, top right: potions, flight, bag.
private struct UtilityRow: View {
    let session: GameSession

    var body: some View {
        let player = session.hud.player
        HStack(spacing: 12) {
            ForEach(Array([ItemID.dewPotion, .nectarVial].enumerated()), id: \.element) { index, item in
                PotionButton(item: item, count: player?.inventory.count(of: item) ?? 0,
                             isCoolingDown: (player?.itemCooldown ?? 0) > 0, glyph: session.glyphs?.quickItems[index]) {
                    session.perform(.quickItem(index))
                }
            }
            if player?.canFly == true {
                let flying = player?.isFlying == true
                RoundButton(symbol: flying ? "arrow.down.to.line" : "wind", size: 48, tint: .cyan, glyph: session.glyphs?.flight) {
                    session.perform(.toggleFlight)
                }
                .accessibilityLabel(flying ? "Land" : "Fly")
                .transition(.scale.combined(with: .opacity))
            }
            RoundButton(symbol: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 48,
                        tint: session.isMuted ? .gray : .white, glyph: nil) {
                session.toggleMute()
            }
            .accessibilityLabel(session.isMuted ? "Unmute" : "Mute")
            RoundButton(symbol: "map.fill", size: 48, glyph: session.glyphs?.map) {
                session.perform(.toggleMap)
            }
            .accessibilityLabel("Map")
            RoundButton(symbol: "bag.fill", size: 48, glyph: session.glyphs?.menu) {
                session.perform(.toggleInventory)
            }
            .accessibilityLabel("Bag")
        }
    }
}

/// Phone haptics for game events. Its own view, so a hit only re-runs this tiny body.
private struct HapticFeedback: View {
    let session: GameSession

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .sensoryFeedback(.impact(weight: .light), trigger: session.feedback.hitsTaken)
            .sensoryFeedback(.impact(weight: .medium), trigger: session.feedback.kills)
            .sensoryFeedback(.success, trigger: session.feedback.levelUps)
            .sensoryFeedback(.error, trigger: session.feedback.failures)
            .sensoryFeedback(.warning, trigger: session.feedback.fainted)
            .sensoryFeedback(.warning, trigger: session.feedback.danger)
            .sensoryFeedback(.selection, trigger: session.feedback.loot)
            .sensoryFeedback(.selection, trigger: session.selection)
    }
}
