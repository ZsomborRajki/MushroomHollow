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
            case .character:
                CharacterPanel(session: session)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            case .map:
                MapPanel(session: session)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            case nil:
                EmptyView()
            }

            if session.isFainted {
                FaintedOverlay(glyph: session.glyphs?.primary, xpLost: session.lastXPLost) {
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

            MuteButton(session: session)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

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

/// Utility row, top right: potions, sitting, flight, and a menu that opens to character, map, and bag.
private struct UtilityRow: View {
    let session: GameSession
    /// Closes again whenever a panel opens (the row leaves the view tree).
    @State private var isMenuOpen = false

    var body: some View {
        let player = session.hud.player
        // Rendered together (see ActionBar).
        GlassEffectContainer(spacing: 4) {
        HStack(spacing: 12) {
            // Each slot shows the potion it would drink right now.
            ForEach(0..<2, id: \.self) { index in
                let item = player?.quickPotion(restoresMP: index == 1) ?? (index == 0 ? .dewPotion : .nectarVial)
                PotionButton(item: item, count: player?.inventory.count(of: item) ?? 0,
                             isCoolingDown: (player?.itemCooldown ?? 0) > 0, glyph: session.glyphs?.quickItems[index]) {
                    session.perform(.quickItem(index))
                }
            }
            if player?.isFlying != true {
                let sitting = player?.isSitting == true
                RoundButton(symbol: "figure.mind.and.body", size: 48, tint: sitting ? .mint : .white, glyph: nil) {
                    session.perform(.toggleSit)
                }
                .accessibilityLabel(sitting ? "Stand up" : "Sit and rest")
            }
            if player?.canFly == true {
                let flying = player?.isFlying == true
                RoundButton(symbol: flying ? "arrow.down.to.line" : "wind", size: 48, tint: .cyan, glyph: session.glyphs?.flight) {
                    session.perform(.toggleFlight)
                }
                .accessibilityLabel(flying ? "Land" : "Fly")
                .transition(.scale.combined(with: .opacity))
            }
            if isMenuOpen {
                MenuButtons(session: session)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            let unspent = player?.unspentStatPoints ?? 0
            RoundButton(symbol: isMenuOpen ? "xmark" : "line.3.horizontal", size: 48,
                        tint: !isMenuOpen && unspent > 0 ? .mint : .white, glyph: nil) {
                withAnimation(.snappy) { isMenuOpen.toggle() }
            }
            .overlay(alignment: .topLeading) {
                if !isMenuOpen { StatPointsBadge(unspent: unspent) }
            }
            .accessibilityLabel(isMenuOpen ? "Close menu" : "Menu")
        }
        }
    }
}

/// The menu's buttons: character, map, bag. Controllers reach these directly (see the glyphs).
private struct MenuButtons: View {
    let session: GameSession

    var body: some View {
        let unspent = session.hud.player?.unspentStatPoints ?? 0
        HStack(spacing: 12) {
            RoundButton(symbol: "figure.stand", size: 48, tint: unspent > 0 ? .mint : .white, glyph: nil) {
                session.perform(.toggleCharacter)
            }
            .overlay(alignment: .topLeading) { StatPointsBadge(unspent: unspent) }
            .accessibilityLabel(unspent > 0 ? "Character, \(unspent) stat points to spend" : "Character")
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

/// Unspent stat points: a Flyff-style nag until they're spent.
private struct StatPointsBadge: View {
    let unspent: Int

    var body: some View {
        if unspent > 0 {
            Text("+\(unspent)")
                .font(.caption2.weight(.heavy).monospacedDigit())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.mint, in: .capsule)
                .foregroundStyle(.black)
                .offset(x: -4, y: -4)
        }
    }
}

/// Bottom left, out of the way: sound on/off.
private struct MuteButton: View {
    let session: GameSession

    var body: some View {
        RoundButton(symbol: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 36,
                    tint: session.isMuted ? .gray : .white, glyph: nil) {
            session.toggleMute()
        }
        .accessibilityLabel(session.isMuted ? "Unmute" : "Mute")
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
