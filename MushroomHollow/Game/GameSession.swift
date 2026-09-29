import Foundation
import GameCore
import Observation
import RealityKit
import SwiftUI
import UIKit

/// What the HUD shows about the current target.
struct TargetInfo: Equatable {
    let id: EntityID
    let name: String
    let level: Int
    let hp: Int
    let maxHP: Int
    /// Mob level relative to the player's: drives the name color.
    let levelDelta: Int
    let isFightingYou: Bool
    /// Attacks on sight (most mobs only fight back).
    let isAggressive: Bool
}

/// The world boss's health bar, shown when you're near it.
struct BossInfo: Equatable {
    let id: EntityID
    let name: String
    let hp: Int
    let maxHP: Int
    let isFighting: Bool
}

/// Slow-changing HUD data. The countdowns inside `player` (skill cooldowns, buff and potion
/// timers) go stale on purpose: read them from `HUDTimers`, so ticking clocks don't redraw the HUD.
struct HUDState: Equatable {
    var player: PlayerStatus?
    var target: TargetInfo?
    var boss: BossInfo?
    var isFainted: Bool { player.map { !$0.stats.isAlive } ?? false }

    /// Equal apart from ticking countdowns (and sub-meter altitude, which the HUD doesn't show).
    func matchesIgnoringCountdowns(_ other: HUDState) -> Bool {
        guard target == other.target, boss == other.boss else { return false }
        guard let a = player, let b = other.player else { return player == nil && other.player == nil }
        // Keep in step with `PlayerStatus`: a field missing here never refreshes the HUD.
        return a.id == b.id && a.stats == b.stats && a.xp == b.xp && a.xpToNextLevel == b.xpToNextLevel
            && a.target == b.target && a.isEngaged == b.isEngaged && a.caps == b.caps
            && a.inventory == b.inventory && a.equipment == b.equipment && a.quests == b.quests
            && a.isSlowed == b.isSlowed && a.playerClass == b.playerClass
            && a.canFly == b.canFly && a.isFlying == b.isFlying && Int(a.altitude) == Int(b.altitude)
            && a.skills.map(\.id) == b.skills.map(\.id)
            && a.skills.map(\.isUnlocked) == b.skills.map(\.isUnlocked)
            && a.skills.map(\.canAfford) == b.skills.map(\.canAfford)
            && a.buffs.map(\.id) == b.buffs.map(\.id)
            && (a.itemCooldown > 0) == (b.itemCooldown > 0)
            && a.pet.slot == b.pet.slot && a.pet.minutesLeft == b.pet.minutesLeft && a.pet.isHungry == b.pet.isHungry
            && a.pet.isSummoned == b.pet.isSummoned && a.pet.isOut == b.pet.isOut && a.pet.awaitingFood == b.pet.awaitingFood
            && a.attributes == b.attributes && a.unspentStatPoints == b.unspentStatPoints
    }
}

/// HUD countdowns, rounded to `step` seconds so they change ~10×/s instead of every tick.
/// Only the rings that draw them read this, so the rest of the HUD stays still.
struct HUDTimers: Equatable {
    struct Countdown: Equatable {
        var remaining: Float = 0
        var total: Float = 0
        var fraction: Double { total > 0 ? Double(min(1, remaining / total)) : 0 }
    }

    static let step: Float = 0.1

    var skills: [SkillID: Countdown] = [:]
    var buffs: [SkillID: Countdown] = [:]

    init() {}

    init(_ status: PlayerStatus?) {
        guard let status else { return }
        for skill in status.skills {
            skills[skill.id] = Countdown(remaining: Self.round(skill.cooldownRemaining), total: skill.cooldownTotal)
        }
        for buff in status.buffs {
            buffs[buff.skill] = Countdown(remaining: Self.round(buff.remaining), total: buff.total)
        }
    }

    private static func round(_ seconds: Float) -> Float {
        (max(0, seconds) / step).rounded(.up) * step
    }
}

/// A damage number or similar label floating up from a point in the world.
struct FloatingText: Identifiable {
    enum Style { case dealt, critical, taken, heal, mana, xp, info }

    let id: Int
    let text: String
    let style: Style
    let worldPosition: SIMD3<Float>
    let born: Double
    var screenPosition: CGPoint?
    var progress: Double = 0
}

/// A line in the loot / progress feed.
struct FeedLine: Identifiable, Equatable {
    let id: Int
    let symbol: String
    let text: String
    let tint: Color
    let expiry: Double
}

struct Banner: Equatable {
    let title: String
    let subtitle: String
}

/// Counters the SwiftUI layer watches to fire haptics.
struct FeedbackTriggers: Equatable {
    var hitsTaken = 0
    var kills = 0
    var levelUps = 0
    var failures = 0
    var fainted = 0
    var loot = 0
    var danger = 0
}

enum Panel: Equatable {
    case inventory
    /// Stats and stat points (Flyff's character window).
    case character
    case npc(NPCID)
    case map
}

/// Live marks for the map screen.
struct MapMarkers {
    struct Mob {
        let position: Vec2
        let isHostile: Bool
        let isFighting: Bool
    }

    var player: (position: Vec2, yaw: Float)?
    /// Where the camera looks, on the ground plane.
    var viewDirection: Vec2 = Vec2(0, -1)
    var mobs: [Mob] = []
    var bossAwake = false
}

/// A hunting ground an active quest sends you to.
struct QuestTarget: Identifiable {
    let id: String
    let title: String
    let center: Vec2
    let radius: Float
}

enum ShopTab: Int, CaseIterable {
    case buy, sell
}

/// One row in an NPC panel.
struct PanelRow: Identifiable, Equatable {
    enum Action: Equatable {
        case buy(ItemID)
        case sell(Gear)
        case upgrade(GearLocation)
        case accept(QuestID)
        case turnIn(QuestID)
        case chooseClass(PlayerClass)
        /// At the pet keeper: bake a whole pile of a material into Kibble.
        case makePetFood(ItemID, count: Int)
        /// At the naturalist: hand in a pile of one material.
        case trade(ItemID, count: Int)
        case none
    }

    let id: String
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    let trailing: String
    let detail: String
    let isEnabled: Bool
    let action: Action
}

/// One cell in the inventory grid. The first two columns hold the equipment slots.
struct InventoryCell: Identifiable, Equatable {
    let id: Int
    let item: ItemID?
    let count: Int
    var upgrade = 0
    let slot: EquipSlot?
    /// The pet slot, under the equipment.
    var isPetSlot = false

    var gear: Gear? { item.map { Gear($0, upgrade: upgrade) } }
}

/// Glue between the world host (simulation), input, camera, and renderer.
/// Driven once per rendered frame by RealityKit's scene update event.
@Observable
final class GameSession {
    // HUD-facing state. Only written when it changes, to keep SwiftUI quiet.
    private(set) var hud = HUDState()
    private(set) var timers = HUDTimers()
    /// Mirrors `hud.isFainted`, so the root view doesn't have to watch all of `hud`.
    private(set) var isFainted = false
    /// XP the last faint cost (shown on the faint screen).
    private(set) var lastXPLost = 0
    private(set) var glyphs: ControllerGlyphs?
    private(set) var floatingTexts: [FloatingText] = []
    private(set) var feed: [FeedLine] = []
    private(set) var toast: String?
    private(set) var banner: Banner?
    private(set) var feedback = FeedbackTriggers()
    private(set) var zone: Zone?
    private(set) var nearbyNPC: NPCID?
    private(set) var panel: Panel?
    private(set) var selection = 0
    private(set) var shopTab = ShopTab.buy
    /// At the blacksmith: spend a Ward Charm on risky upgrades.
    private(set) var protectUpgrades = false
    /// On the character panel: points picked but not yet confirmed.
    private(set) var pendingPoints = Attributes()
    /// Half the width of ground the map shows, in meters (pinch or LB/RB to change).
    private(set) var mapSpan = GameSession.mapFullSpan
    /// Sound off (remembered on this device).
    private(set) var isMuted = UserDefaults.standard.bool(forKey: GameSession.mutedKey)
    /// Where the map is centered after panning; nil follows you (or shows the whole hollow, zoomed out).
    private(set) var mapCenter: Vec2?
    private(set) var timeOfDay: Float = 0.4
    private(set) var debugText = ""

    var isGamepadConnected: Bool { glyphs != nil }

    @ObservationIgnored let host: LocalWorldHost
    @ObservationIgnored let input = InputHub()
    @ObservationIgnored private let rumble = Rumble()
    @ObservationIgnored private let gameCenter = GameCenter()
    @ObservationIgnored private var shakeUntil: Double = 0
    @ObservationIgnored private var shakeStrength: Float = 0
    @ObservationIgnored let renderer: WorldRenderer
    @ObservationIgnored private let store: SaveStore?
    @ObservationIgnored private var camera = OrbitCamera()
    @ObservationIgnored private var projector: RealityViewCameraContent?
    @ObservationIgnored private var updateSubscription: EventSubscription?
    /// Frames left before the color grade can be installed (see `installColorGradeWhenReady`).
    @ObservationIgnored private var colorGradeDelay = 3
    @ObservationIgnored private var elapsed: Double = 0
    @ObservationIgnored private var slowRefresh: Double = 0
    @ObservationIgnored private var hudTick: UInt64?
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var toastExpiry: Double = 0
    @ObservationIgnored private var bannerExpiry: Double = 0
    @ObservationIgnored private var nextAutosave: Double = 20
    @ObservationIgnored private var saveRequested = false
    @ObservationIgnored private var paintedMap: UIImage?

    static let floaterLifetime: Double = 1.1
    static let maxFloatingTexts = 24
    /// Bag grid columns. The equipment slots form a small paper-doll grid to its left.
    static let inventoryColumns = 6
    static let equipmentColumns = 2
    static let firstBagCell = EquipSlot.allCases.count
    /// The pet slot sits under the equipment grid, but comes last so bag indices stay put.
    static let petCell = firstBagCell + Inventory.capacity
    static let autosaveInterval: Double = 20

    #if DEBUG
    /// `-autofight` launch argument: start in the snail glade and fight automatically.
    @ObservationIgnored private let autoFight = ProcessInfo.processInfo.arguments.contains("-autofight")
    @ObservationIgnored private var autoFightClock: Double = 0
    /// `-attackloop`: the player attacks thin air on repeat (and blocks now and then), for checking animations.
    @ObservationIgnored private let attackLoop = ProcessInfo.processInfo.arguments.contains("-attackloop")
    @ObservationIgnored private var attackLoopClock: Double = 0
    @ObservationIgnored private var attackLoopCount = 0
    @ObservationIgnored private var debugClimbUntil: Double?
    #endif

    init() {
        #if DEBUG
        let debug = DebugLaunch()
        let throwaway = debug.isThrowaway
        #else
        let throwaway = false
        #endif
        store = try? SaveStore(inMemory: throwaway)
        #if DEBUG
        if debug.resetSave { store?.deleteAll() }
        let profile = debug.profile ?? store?.load() ?? .newCharacter
        #else
        let profile = store?.load() ?? .newCharacter
        #endif

        #if DEBUG
        host = LocalWorldHost(profile: profile, startTimeOfDay: debug.timeOfDay ?? 0.32)
        #else
        host = LocalWorldHost(profile: profile)
        #endif
        renderer = WorldRenderer(map: host.map)
        renderer.sounds.isMuted = isMuted
        // Start behind the player, looking at the giant trunk.
        if let player = host.currentSnapshot.entity(host.localPlayerID) {
            camera.yaw = player.yaw + .pi
        }
        #if DEBUG
        if let spot = debug.spawnPoint(in: host.map) {
            host.teleportPlayer(to: spot)
        }
        panel = debug.panel
        if panel == .inventory { selection = Self.firstBagCell }
        if debug.arguments.contains("-portrait"), let player = host.currentSnapshot.entity(host.localPlayerID) {
            // Close-up from the front (or `-portrait <degrees>` around), for checking the character model.
            camera.yaw = player.yaw + (debug.value(after: "-portrait").flatMap(Float.init) ?? 0) * .pi / 180
            camera.pitch = 0.12
            camera.distance = 3
        }
        if debug.arguments.contains("-owl"), let arena = host.map.bossArena {
            host.summonWorldBoss()
            host.teleportPlayer(to: arena.center + (arena.center - arena.perch).normalizedOrZero * 6)
            camera.yaw = AngleMath.yaw(facing: arena.center - arena.perch) + .pi
        }
        if debug.arguments.contains("-fly") {
            host.send(.toggleFlight)
            input.touchClimb = 1
            debugClimbUntil = 2.5
        }
        #endif
    }

    func attach(to content: inout RealityViewCameraContent) {
        content.camera = .virtual
        content.add(renderer.root)
        content.audioListener = renderer.camera
        projector = content
        let sounds = renderer.sounds
        Task { await sounds.load() }
        gameCenter.authenticate()
        updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.frame(deltaTime: event.deltaTime)
        }
    }

    func setViewportSize(_ size: CGSize) {
        guard size.height > 0 else { return }
        renderer.viewportAspect = Float(size.width / size.height)
    }

    /// RealityKit traps when custom post-processing is set before the active camera has
    /// rendered (it force-unwraps the camera's view descriptors), so wait a few frames
    /// instead of setting it in the `RealityView` make closure.
    private func installColorGradeWhenReady() {
        guard colorGradeDelay > 0 else { return }
        colorGradeDelay -= 1
        guard colorGradeDelay == 0 else { return }
        projector?.renderingEffects.customPostProcessing = .effect(ColorGradeEffect(settings: renderer.atmosphere.grade))
    }

    func saveNow() {
        guard let profile = host.simulation.profile(of: host.localPlayerID) else { return }
        store?.save(profile)
        saveRequested = false
        nextAutosave = elapsed + Self.autosaveInterval
    }

    // MARK: - Input from the SwiftUI overlay

    func setTouchMove(_ stick: SIMD2<Float>) { input.touchMove = stick }
    func setTouchClimb(_ amount: Float) { input.touchClimb = amount }
    func touchLook(_ translation: CGSize) { input.addTouchLook(translation: translation) }
    func zoom(by meters: Float) { input.addZoom(meters) }
    func perform(_ action: InputAction) { input.enqueue(action) }

    func tapped(_ entity: Entity) {
        var current: Entity? = entity
        while let e = current {
            if let drop = e.components[GroundDropComponent.self] {
                host.send(.pickupDrop(drop.id))
                return
            }
            if let link = e.components[SimEntityComponent.self] {
                input.enqueue(.select(link.id))
                return
            }
            current = e.parent
        }
    }

    /// Touch: pick a row/cell; tapping the selected one again activates it.
    func tapSelection(_ index: Int) {
        if selection == index {
            activateSelection()
        } else {
            selection = index
            renderer.sounds.playInterface(.uiMove)
        }
    }

    static let mutedKey = "soundMuted"

    func toggleMute() {
        isMuted.toggle()
        renderer.sounds.isMuted = isMuted
        UserDefaults.standard.set(isMuted, forKey: Self.mutedKey)
        if !isMuted { renderer.sounds.playInterface(.uiConfirm) }
    }

    func setShopTab(_ tab: ShopTab) {
        shopTab = tab
        selection = 0
    }

    func setProtectUpgrades(_ protect: Bool) {
        protectUpgrades = protect
        renderer.sounds.playInterface(.uiMove)
    }

    func closePanel() {
        if panel != nil { renderer.sounds.playInterface(.uiMove) }
        gameCenter.showAccessPoint(false)
        panel = nil
        selection = 0
        pendingPoints = Attributes()
    }

    private func openPanel(_ newPanel: Panel) {
        panel = newPanel
        pendingPoints = Attributes()
        gameCenter.showAccessPoint(newPanel == .inventory)
        selection = newPanel == .inventory ? Self.firstBagCell : 0
        shopTab = .buy
        renderer.sounds.playInterface(.uiConfirm)
    }

    // MARK: - Stat points

    /// Points left to hand out on the character panel, counting the ones already picked.
    var pointsLeftToPick: Int {
        (hud.player?.unspentStatPoints ?? 0) - pendingPoints.spent
    }

    /// Picks (or un-picks) one point; nothing is spent until confirmed.
    func adjustPendingPoint(_ attribute: Attribute, by step: Int) {
        guard step > 0 ? pointsLeftToPick > 0 : pendingPoints[attribute] > 0 else {
            if step > 0 { renderer.sounds.playInterface(.error) }
            return
        }
        pendingPoints[attribute] += step
        renderer.sounds.playInterface(.uiMove)
    }

    func confirmPendingPoints() {
        guard pendingPoints.spent > 0 else { return }
        host.send(.spendStatPoints(pendingPoints))
    }

    func clearPendingPoints() {
        pendingPoints = Attributes()
        renderer.sounds.playInterface(.uiMove)
    }

    /// Full stats as they'd be with the picked points spent (for the before → after preview).
    var previewStats: CombatStats? {
        guard let player = hud.player else { return nil }
        return Progression.playerStats(level: player.stats.level, bonus: GameSimulation.equipmentBonus(player.equipment),
                                       playerClass: player.playerClass,
                                       weapon: player.equipment[.weapon]?.definition.weaponType,
                                       attributes: player.attributes + pendingPoints)
    }

    // MARK: - Frame

    private func frame(deltaTime: TimeInterval) {
        let dt = Float(min(deltaTime, 0.1))
        elapsed += deltaTime
        installColorGradeWhenReady()

        #if DEBUG
        if autoFight { driveAutoFight(deltaTime: deltaTime) }
        if attackLoop, let stats = host.currentSnapshot.viewer?.stats {
            attackLoopClock -= deltaTime
            if attackLoopClock <= 0 {
                attackLoopClock = Double(stats.attackInterval)
                attackLoopCount += 1
                renderer.debugAttack(host.localPlayerID, block: attackLoopCount.isMultiple(of: 5), time: elapsed)
            }
        }
        if let until = debugClimbUntil, elapsed > until {
            input.touchClimb = 0
            debugClimbUntil = nil
        }
        #endif
        let flying = host.currentSnapshot.viewer?.isFlying ?? false
        let frameInput = input.poll(deltaTime: dt, menuOpen: panel != nil, flying: flying)
        camera.apply(look: frameInput.look, zoom: frameInput.zoom)
        for action in frameInput.actions { handle(action) }
        host.send(.move(camera.worldDirection(forStick: frameInput.move)))
        if flying { host.send(.climb(frameInput.climb)) }

        host.advance(by: deltaTime)
        renderer.render(host: host, time: elapsed)
        for event in host.drainEvents() { handle(event) }

        // Big fights need a wider view.
        camera.minimumDistance = hud.boss != nil ? 16 : 0
        if let player = renderer.renderedPosition(of: host.localPlayerID) {
            camera.follow(player, deltaTime: dt)
        }
        let map = host.map
        var cameraPosition = camera.position(avoidingTrunkRadius: map.trunkCollisionRadius) { map.surfaceHeight(at: $0) }
        if elapsed < shakeUntil {
            // Screen shake for big impacts, fading out.
            let fade = Float((shakeUntil - elapsed) / 0.4)
            cameraPosition += SIMD3(sin(Float(elapsed) * 83), sin(Float(elapsed) * 97), cos(Float(elapsed) * 71)) * shakeStrength * fade
        }
        renderer.placeCamera(at: cameraPosition, lookingAt: camera.focus)

        updateHUD()
        updateFloatingTexts()
        updateSlowState(deltaTime: deltaTime)
    }

    #if DEBUG
    private func driveAutoFight(deltaTime: TimeInterval) {
        autoFightClock += deltaTime
        guard autoFightClock > 0.5, let me = host.currentSnapshot.viewer else { return }
        autoFightClock = 0
        if !me.isEngaged || !me.stats.isAlive { input.enqueue(.primary) }
        if let ready = me.skills.firstIndex(where: \.isReady) {
            input.enqueue(.skill(ready))
        }
        if me.stats.hp * 3 < me.stats.maxHP { input.enqueue(.quickItem(0)) }
    }
    #endif

    // MARK: - Actions → commands

    private func handle(_ action: InputAction) {
        let snapshot = host.currentSnapshot
        guard let me = snapshot.viewer, let myPosition = snapshot.entity(me.id)?.position else { return }

        switch action {
        case .primary:
            let fighting = me.isEngaged && me.target.flatMap { snapshot.entity($0)?.isAlive } == true
            if !me.stats.isAlive {
                host.send(.respawn)
            } else if let npc = nearbyNPC, !fighting {
                openPanel(.npc(npc))
            } else if let target = me.target, snapshot.entity(target)?.isAlive == true {
                host.send(.target(target, engage: true))
            } else if let nearest = snapshot.nearestHostile(to: myPosition) {
                host.send(.target(nearest, engage: true))
            }

        case let .cycleTarget(step):
            if let next = snapshot.cycleTarget(from: myPosition, current: me.target, step: step) {
                host.send(.target(next, engage: false))
            }

        case .clearTarget:
            host.send(.target(nil, engage: false))

        case let .skill(index):
            guard me.skills.indices.contains(index) else { return }
            let skill = me.skills[index].id
            // Flyff-friendly: a targeted skill with nothing selected picks the nearest mob.
            if skill.definition.needsTarget, me.target == nil, let nearest = snapshot.nearestHostile(to: myPosition) {
                host.send(.target(nearest, engage: false))
            }
            host.send(.useSkill(skill))

        case let .select(id):
            guard id != me.id, let entity = snapshot.entity(id) else { return }
            if case let .npc(npc) = entity.kind {
                if entity.position.xz.distance(to: myPosition.xz) <= NPCID.interactionRange {
                    openPanel(.npc(npc))
                } else {
                    showToast("Walk closer to talk to \(npc.definition.name)")
                }
            } else {
                host.send(.target(id, engage: true))
            }

        case .toggleInventory:
            if panel == .inventory {
                closePanel()
            } else {
                openPanel(.inventory)
            }

        case .toggleMap:
            if panel == .map {
                closePanel()
            } else {
                openPanel(.map)
            }

        case let .quickItem(index):
            host.send(.useItem(index == 0 ? .dewPotion : .nectarVial))

        case .toggleFlight:
            host.send(.toggleFlight)

        case .togglePet:
            togglePet()

        case .toggleCharacter:
            if panel == .character {
                closePanel()
            } else {
                openPanel(.character)
            }

        case let .menu(input):
            handleMenu(input)
        }
    }

    // MARK: - Panels

    private func handleMenu(_ input: MenuInput) {
        switch input {
        case .back:
            closePanel()
        case .confirm where panel == .map:
            cycleMapZoom()
        case .previousTab where panel == .map, .nextTab where panel == .map:
            stepMapZoom(zoomIn: input == .nextTab)
        case .confirm:
            activateSelection()
        case .previousTab where panel == .inventory, .nextTab where panel == .inventory:
            openPanel(.character) // the bag and the character sheet sit side by side, like tabs
        case .previousTab where panel == .character, .nextTab where panel == .character:
            openPanel(.inventory)
        case .previousTab, .nextTab:
            guard case let .npc(npc) = panel else { return }
            if npc.definition.isShopkeeper { setShopTab(shopTab == .buy ? .sell : .buy) }
            if npc.definition.upgradesGear { setProtectUpgrades(!protectUpgrades) }
        case .up, .down, .left, .right:
            let before = selection
            moveSelection(input)
            if selection != before { renderer.sounds.playInterface(.uiMove) }
        }
    }

    private func moveSelection(_ direction: MenuInput) {
        switch panel {
        case .inventory:
            // The equipment grid (row by row), then the bag grid to its right.
            let columns = Self.inventoryColumns
            let slotColumns = Self.equipmentColumns
            let slotRows = Self.firstBagCell / slotColumns + 1 // the pet slot is the last row
            let bagRows = Inventory.capacity / columns
            let inSlots = selection < Self.firstBagCell || selection == Self.petCell
            let bagIndex = selection - Self.firstBagCell
            var column = selection == Self.petCell ? slotColumns - 1 : inSlots ? selection % slotColumns : slotColumns + bagIndex % columns
            var row = selection == Self.petCell ? slotRows - 1 : inSlots ? selection / slotColumns : bagIndex / columns
            switch direction {
            case .left: column = max(0, column - 1)
            case .right: column = min(slotColumns + columns - 1, column + 1)
            case .up: row = max(0, row - 1)
            case .down: row += 1
            default: break
            }
            row = min(row, (column < slotColumns ? slotRows : bagRows) - 1)
            if column < slotColumns, row == slotRows - 1 {
                selection = Self.petCell
            } else {
                selection = column < slotColumns ? row * slotColumns + column : Self.firstBagCell + row * columns + column - slotColumns
            }
        case .character:
            // The four attributes, then Confirm. Left/right take a point back or put one in.
            switch direction {
            case .up: selection = max(0, selection - 1)
            case .down: selection = min(Attribute.allCases.count, selection + 1)
            case .left, .right:
                guard Attribute.allCases.indices.contains(selection) else { return }
                adjustPendingPoint(Attribute.allCases[selection], by: direction == .right ? 1 : -1)
            default: break
            }
        case .npc:
            let count = npcRows.count
            guard count > 0 else { return }
            if direction == .up { selection = max(0, selection - 1) }
            if direction == .down { selection = min(count - 1, selection + 1) }
        case .map:
            let step = mapSpan * 0.3
            let offset: Vec2 = switch direction {
            case .up: Vec2(0, -step)
            case .down: Vec2(0, step)
            case .left: Vec2(-step, 0)
            default: Vec2(step, 0)
            }
            setMapView(span: mapSpan, center: effectiveMapCenter + offset)
        case nil:
            break
        }
    }

    private func activateSelection() {
        switch panel {
        case .inventory:
            guard let cell = inventoryCells.first(where: { $0.id == selection }), let item = cell.item else { return }
            if cell.isPetSlot {
                togglePet()
                return
            }
            if let slot = cell.slot {
                host.send(.unequip(slot))
                return
            }
            switch item.definition.kind {
            case .consumable: host.send(.useItem(item))
            case .equipment: host.send(.equip(item, upgrade: cell.upgrade))
            case .material where item == .amberShard || item == .wardCharm: showToast("Bring it to Shiitake to upgrade gear")
            case .material: showToast("Trade materials to Porcini for XP, or sell them to Chanterelle")
            case .glider:
                closePanel()
                host.send(.toggleFlight)
            case .pet:
                // Into the slot and straight out to play.
                host.send(.slotPet(item))
                host.send(.summonPet)
            case .petFood:
                host.send(.useItem(item))
            }
        case let .npc(npc):
            guard npcRows.indices.contains(selection) else { return }
            let row = npcRows[selection]
            guard row.isEnabled else { return }
            switch row.action {
            case let .buy(item): host.send(.buy(item, from: npc))
            case let .sell(gear): host.send(.sell(gear.item, count: 1, upgrade: gear.upgrade, to: npc))
            case let .upgrade(location): host.send(.upgrade(location, protect: protectUpgrades))
            case let .accept(quest): host.send(.acceptQuest(quest))
            case let .turnIn(quest): host.send(.completeQuest(quest))
            case let .chooseClass(playerClass): host.send(.chooseClass(playerClass))
            case let .makePetFood(item, count): host.send(.makePetFood(item, count: count, at: npc))
            case let .trade(item, count): host.send(.tradeMaterials(item, count: count, at: npc))
            case .none: break
            }
        case .character:
            if Attribute.allCases.indices.contains(selection) {
                adjustPendingPoint(Attribute.allCases[selection], by: 1)
            } else {
                confirmPendingPoints()
            }
        case .map:
            cycleMapZoom()
        case nil:
            break
        }
    }

    // MARK: - Map

    static let mapFullSpan: Float = 306
    static let mapSpanRange: ClosedRange<Float> = 30...mapFullSpan
    /// Zoom stops for buttons: the whole hollow, a region, the area around you.
    private static let mapZoomStops: [Float] = [mapFullSpan, 125, 55]

    /// What the map is centered on right now.
    var effectiveMapCenter: Vec2 {
        if let mapCenter { return mapCenter }
        guard mapSpan < Self.mapFullSpan * 0.9 else { return .zero }
        return host.currentSnapshot.entity(host.localPlayerID)?.position.xz ?? .zero
    }

    /// Pinch, drag, and button zoom all end here. Keeps the view over the hollow.
    func setMapView(span: Float, center: Vec2?) {
        mapSpan = min(max(span, Self.mapSpanRange.lowerBound), Self.mapSpanRange.upperBound)
        guard var center else {
            mapCenter = nil
            return
        }
        let limit = max(0, Self.mapFullSpan - mapSpan)
        if center.length > limit { center = center.normalizedOrZero * limit }
        mapCenter = center
    }

    /// Back to following you.
    func recenterMap() {
        mapCenter = nil
        renderer.sounds.playInterface(.uiMove)
    }

    /// A / Space / the button: whole hollow → region → around you → whole hollow.
    func cycleMapZoom() {
        let next = Self.mapZoomStops.first { $0 < mapSpan - 1 } ?? Self.mapFullSpan
        setMapView(span: next, center: nil)
        renderer.sounds.playInterface(.uiMove)
    }

    /// LB/RB, Q/E: one stop in or out, keeping the current center.
    func stepMapZoom(zoomIn: Bool) {
        let span = zoomIn ? (Self.mapZoomStops.first { $0 < mapSpan - 1 } ?? Self.mapSpanRange.lowerBound)
                          : (Self.mapZoomStops.last { $0 > mapSpan + 1 } ?? Self.mapFullSpan)
        setMapView(span: span, center: mapCenter)
        renderer.sounds.playInterface(.uiMove)
    }

    var map: WorldMap { host.map }

    /// The illustrated map, painted the first time it's opened.
    var mapImage: UIImage {
        if let paintedMap { return paintedMap }
        let image = MapPainter.paint(host.map, ground: renderer.groundPainting)
        paintedMap = image
        return image
    }

    /// Where you are and what's around you, read fresh each time (the map redraws a few times a second).
    var mapMarkers: MapMarkers {
        let snapshot = host.currentSnapshot
        var markers = MapMarkers(viewDirection: camera.groundForward)
        if let me = snapshot.entity(host.localPlayerID) {
            markers.player = (me.position.xz, me.yaw)
            markers.mobs = snapshot.entities.compactMap { entity in
                guard case let .mob(kind) = entity.kind, entity.isAlive, kind != .owl,
                      entity.position.xz.distance(to: me.position.xz) < 90 else { return nil }
                return MapMarkers.Mob(position: entity.position.xz, isHostile: entity.isAggressive,
                                      isFighting: entity.target == host.localPlayerID)
            }
        }
        if let boss = host.simulation.worldBoss { markers.bossAwake = snapshot.entity(boss)?.isAlive == true }
        return markers
    }

    /// Hunting grounds your active quests send you to.
    var questTargets: [QuestTarget] {
        (hud.player?.quests ?? []).flatMap { status -> [QuestTarget] in
            guard case .active = status.state else { return [] }
            let quest = status.id.definition
            let kinds: [MobKind] = switch quest.objective {
            case let .defeat(kind, _): [kind]
            case let .collect(item, _): MobKind.allCases.filter { $0.canDrop(item) }
            }
            if kinds.contains(.owl), let arena = host.map.bossArena {
                return [QuestTarget(id: "\(quest.id)-owl", title: quest.title, center: arena.center, radius: arena.radius)]
            }
            return host.map.mobSpawns.filter { kinds.contains($0.kind) }.map { area in
                QuestTarget(id: "\(quest.id)-\(area.kind)", title: quest.title, center: area.center, radius: area.radius)
            }
        }
    }

    /// The equipment cells, then the bag.
    var inventoryCells: [InventoryCell] {
        guard let player = hud.player else { return [] }
        var cells = EquipSlot.allCases.enumerated().map { index, slot in
            InventoryCell(id: index, item: player.equipment[slot]?.item, count: 1, upgrade: player.equipment[slot]?.upgrade ?? 0, slot: slot)
        }
        let stacks = player.inventory.stacks
        for index in 0..<Inventory.capacity {
            let stack = index < stacks.count ? stacks[index] : nil
            cells.append(InventoryCell(id: Self.firstBagCell + index, item: stack?.item, count: stack?.count ?? 0,
                                       upgrade: stack?.upgrade ?? 0, slot: nil))
        }
        cells.append(InventoryCell(id: Self.petCell, item: player.pet.slot, count: 1, slot: nil, isPetSlot: true))
        return cells
    }

    var npcRows: [PanelRow] {
        guard case let .npc(npc) = panel, let player = hud.player else { return [] }
        if npc.definition.isShopkeeper {
            switch shopTab {
            case .buy:
                return npc.definition.shopStock.map { item in
                    let definition = item.definition
                    let price = definition.buyPrice ?? 0
                    return PanelRow(
                        id: "buy-\(item.rawValue)", symbol: item.symbol, tint: item.tint,
                        title: definition.name,
                        subtitle: [item.statLine, definition.requiredClass.map { "\($0.definition.name) only" },
                                   definition.requiredLevel > 1 ? "Lv \(definition.requiredLevel)" : nil]
                            .compactMap { $0 }.joined(separator: " · "),
                        trailing: "\(price) caps", detail: definition.description,
                        isEnabled: player.caps >= price, action: .buy(item))
                }
            case .sell:
                return player.inventory.stacks.enumerated().map { index, stack in
                    let gear = stack.gear
                    return PanelRow(
                        id: "sell-\(index)-\(stack.item.rawValue)", symbol: stack.item.symbol, tint: stack.item.tint,
                        title: stack.count > 1 ? "\(gear.displayName) ×\(stack.count)" : gear.displayName,
                        subtitle: gear.statLine ?? "Material",
                        trailing: "+\(gear.sellPrice)", detail: gear.definition.description,
                        isEnabled: true, action: .sell(gear))
                }
            }
        }
        if npc.definition.upgradesGear { return upgradeRows(player) }
        // Things to do first, finished business last.
        func priority(_ state: QuestState) -> Int {
            switch state {
            case .readyToTurnIn: 0
            case .available: 1
            case .active: 2
            case .tooLowLevel: 3
            case .completed, .hidden: 4
            }
        }
        let quests = player.quests.sorted { priority($0.state) < priority($1.state) }
        var classRows: [PanelRow] = []
        if npc == .elderMorel, player.playerClass == nil {
            if player.stats.level >= PlayerClass.requiredLevel {
                classRows = PlayerClass.allCases.map { playerClass in
                    let definition = playerClass.definition
                    let skills = definition.skills.map(\.definition.name).joined(separator: ", ")
                    return PanelRow(
                        id: "class-\(playerClass.rawValue)", symbol: playerClass.symbol, tint: playerClass.tint,
                        title: "Become a \(definition.name)", subtitle: definition.role, trailing: "Choose",
                        detail: "\(definition.description)\n\nNew skills: \(skills)\n\nThis choice is permanent.",
                        isEnabled: true, action: .chooseClass(playerClass))
                }
            } else {
                classRows = [PanelRow(
                    id: "class-locked", symbol: "signpost.right.and.left.fill", tint: .gray,
                    title: "Choose your path", subtitle: "Guard, Thornshot, Sporecaster, or Dewkeeper",
                    trailing: "Lv \(PlayerClass.requiredLevel)",
                    detail: "Come back at level \(PlayerClass.requiredLevel) and Elder Morel will help you choose a calling.",
                    isEnabled: false, action: .none)]
            }
        }
        let rows: [PanelRow] = classRows + quests.compactMap { status -> PanelRow? in
            guard status.id.definition.giver == npc else { return nil }
            let quest = status.id.definition
            let detail = "\(quest.story)\n\n\(quest.objective.summary)\nReward: \(quest.rewardLine)"
            func row(_ symbol: String, _ tint: Color, _ trailing: String, _ enabled: Bool, _ action: PanelRow.Action) -> PanelRow {
                PanelRow(id: quest.id.rawValue, symbol: symbol, tint: tint, title: quest.title,
                         subtitle: quest.isRepeatable ? "\(quest.objective.summary) · pays \(quest.rewardCaps) caps" : quest.objective.summary,
                         trailing: trailing, detail: detail,
                         isEnabled: enabled, action: action)
            }
            switch status.state {
            case .hidden: return nil
            case let .tooLowLevel(required): return row("lock.fill", .gray, "Lv \(required)", false, .none)
            case .available: return row("exclamationmark.circle.fill", .yellow, "Accept", true, .accept(quest.id))
            case let .active(progress, goal): return row("hourglass", .orange, "\(progress)/\(goal)", false, .none)
            case .readyToTurnIn: return row("checkmark.seal.fill", .green, "Turn in", true, .turnIn(quest.id))
            case .completed: return row("checkmark.circle", .secondary, "Done", false, .none)
            }
        }
        if npc.definition.makesPetFood { return rows + petFoodRows(player) }
        if npc.definition.buysMaterials { return rows + materialRows(player) }
        return rows
    }

    /// At the naturalist: every mob material in the bag, a whole pile at a time.
    private func materialRows(_ player: PlayerStatus) -> [PanelRow] {
        var piles: [(item: ItemID, count: Int)] = []
        for stack in player.inventory.stacks where stack.item.bounty != nil {
            if let index = piles.firstIndex(where: { $0.item == stack.item }) {
                piles[index].count += stack.count
            } else {
                piles.append((stack.item, stack.count))
            }
        }
        // Collect quests still counting on a material get a warning before it's handed over.
        let wanted: [ItemID: String] = Dictionary(player.quests.compactMap { status in
            guard case .active = status.state, case let .collect(item, _) = status.id.definition.objective else { return nil }
            return (item, status.id.definition.title)
        }, uniquingKeysWith: { first, _ in first })
        return piles.compactMap { item, count in
            guard let bounty = item.bounty else { return nil }
            let xp = bounty.xp(forPlayerLevel: player.stats.level)
            let warning = wanted[item].map { "\n\nCareful: \"\($0)\" still needs these." } ?? ""
            return PanelRow(
                id: "trade-\(item.rawValue)", symbol: item.symbol, tint: item.tint,
                title: "\(item.definition.name) ×\(count)",
                subtitle: wanted[item].map { "Needed for \($0)" } ?? "From \(bounty.source.pluralName)",
                trailing: "+\(xp * count) XP",
                detail: """
                    Porcini files all \(count) under \(bounty.source.pluralName), paying \(xp) XP and \(bounty.caps) caps each: \
                    \(xp * count) XP and \(bounty.caps * count) caps in all. Specimens from critters far below your level teach you less.\(warning)
                    """,
                isEnabled: true, action: .trade(item, count: count))
        }
    }

    /// At the pet keeper: every mob material in the bag, a whole pile at a time.
    private func petFoodRows(_ player: PlayerStatus) -> [PanelRow] {
        var piles: [(item: ItemID, count: Int)] = []
        for stack in player.inventory.stacks where stack.item.kibbleValue != nil {
            if let index = piles.firstIndex(where: { $0.item == stack.item }) {
                piles[index].count += stack.count
            } else {
                piles.append((stack.item, stack.count))
            }
        }
        let kibble = player.inventory.count(of: .kibble)
        return piles.map { item, count in
            let value = item.kibbleValue ?? 0
            // Like the sim: the pile leaves the bag first, which may free a slot.
            var bag = player.inventory
            bag.remove(item, count: count)
            let fits = bag.canAdd(.kibble, count: count * value)
            return PanelRow(
                id: "kibble-\(item.rawValue)", symbol: item.symbol, tint: item.tint,
                title: "\(item.definition.name) ×\(count)", subtitle: "\(value) Kibble each",
                trailing: "\(count * value) Kibble",
                detail: """
                    Truffle bakes all \(count) into \(count * value) Kibble. You have \(kibble).
                    One Kibble keeps a pet fed for 3 minutes; a full belly lasts half an hour.
                    """,
                isEnabled: fits, action: .makePetFood(item, count: count))
        }
    }

    /// Everything the blacksmith can work on: worn gear first, then the bag.
    private func upgradeRows(_ player: PlayerStatus) -> [PanelRow] {
        let worn: [(GearLocation, Gear, String)] = EquipSlot.allCases.compactMap { slot in
            player.equipment[slot].map { (.equipped(slot), $0, "Equipped") }
        }
        let carried: [(GearLocation, Gear, String)] = player.inventory.stacks
            .filter { $0.item.definition.isUpgradable }
            .map { (.bag($0.gear), $0.gear, "In bag") }
        let amber = player.inventory.count(of: .amberShard)
        let charms = player.inventory.count(of: .wardCharm)

        return (worn + carried).enumerated().map { index, entry in
            let (location, gear, place) = entry
            let id = "upgrade-\(index)-\(gear.item.rawValue)-\(gear.upgrade)"
            let target = gear.upgrade + 1
            guard target <= Upgrade.maxLevel else {
                return PanelRow(id: id, symbol: gear.item.symbol, tint: gear.item.tint, title: gear.displayName,
                                subtitle: "\(place) · fully upgraded", trailing: "MAX",
                                detail: "\(gear.statLine ?? "")\n\nThis can't get any better.", isEnabled: false, action: .none)
            }
            let chance = Upgrade.chance(toReach: target)
            let stones = Upgrade.amberCost(toReach: target)
            let caps = Upgrade.capsCost(of: gear.item, toReach: target)
            let risk = Upgrade.risk(toReach: target)
            let protected = protectUpgrades && risk != .none
            let failure = switch (risk, protected) {
            case (.none, _): "If it fails, only the materials are lost."
            case (_, true): "If it fails, the Ward Charm keeps it at +\(gear.upgrade) (uses 1 of \(charms))."
            case (.downgrade, false): "If it fails, it drops to +\(gear.upgrade - 1)."
            case (.destroy, false): "If it fails, it is destroyed! Turn on the Ward Charm to prevent that."
            }
            let next = Gear(gear.item, upgrade: target)
            let detail = """
                \(gear.statLine ?? "") → \(next.statLine ?? "")
                \(stones) Amber Shard\(stones == 1 ? "" : "s") (have \(amber)) · \(caps) caps · \(StatBonus.percent(chance)) chance
                \(failure)
                """
            let affordable = amber >= stones && player.caps >= caps && (!protected || charms > 0)
            return PanelRow(id: id, symbol: gear.item.symbol, tint: gear.item.tint, title: gear.displayName,
                            subtitle: "\(place) · to +\(target): \(stones) amber, \(caps) caps",
                            trailing: StatBonus.percent(chance), detail: detail,
                            isEnabled: affordable, action: .upgrade(location))
        }
    }

    /// Active quests for the HUD tracker.
    var trackedQuests: [(quest: QuestDefinition, text: String, ready: Bool)] {
        (hud.player?.quests ?? []).compactMap { status in
            switch status.state {
            case let .active(progress, goal): (status.id.definition, "\(progress)/\(goal)", false)
            case .readyToTurnIn: (status.id.definition, "Return to \(status.id.definition.giver.definition.name)", true)
            default: nil
            }
        }
    }

    // MARK: - Events → presentation

    private func handle(_ event: WorldEvent) {
        let me = host.localPlayerID
        switch event {
        case let .damage(source, target, amount, isCritical, skill):
            let attack = renderer.attackStyle(of: source)
            if skill == nil, attack.ranged, let head = renderer.headPosition(of: source), let to = renderer.headPosition(of: target) {
                // Read the muzzle before the shot animation moves it.
                let from = renderer.muzzle(of: source) ?? head - [0, 0.6, 0]
                let aim = to - [0, 0.4, 0]
                switch attack.weapon {
                case .bow: renderer.effects.arrow(from: from, to: aim, time: elapsed)
                case .wand: renderer.effects.projectile(from: from, to: aim, color: UIColor(red: 0.8, green: 0.5, blue: 1, alpha: 1), time: elapsed)
                case .staff: renderer.effects.projectile(from: from, to: aim, color: UIColor(red: 0.55, green: 0.9, blue: 1, alpha: 1), size: 0.12, time: elapsed)
                default:
                    let color = renderer.playerClass(of: source) == .thornshot ? Palette.leaf : Palette.sporeGlow
                    renderer.effects.projectile(from: from, to: aim, color: color, time: elapsed)
                }
                renderer.sounds.play(.shoot, from: renderer.entity(for: source), gain: -6)
            } else if skill == nil {
                renderer.sounds.play(.swing, from: renderer.entity(for: source), gain: attack.weapon == .maul ? -4 : -8)
                if attack.weapon == .maul, let position = renderer.renderedPosition(of: target) {
                    // The head lands a beat after the swing starts: dust rings out from the impact.
                    renderer.effects.shockwave(at: position, radius: 1.3, color: UIColor(red: 0.85, green: 0.75, blue: 0.55, alpha: 1),
                                               duration: 0.35, delay: 0.26, time: elapsed)
                }
            }
            renderer.playAttack(source: source, target: target, time: elapsed)
            renderer.sounds.play(isCritical ? .crit : (target == me ? .hurt : .hit), from: renderer.entity(for: target), gain: -2)
            if target == me { rumble.play(.light) }
            if source == me, isCritical { rumble.play(.light) }
            let style: FloatingText.Style = target == me ? .taken : (isCritical ? .critical : .dealt)
            float(isCritical ? "\(amount)!" : "\(amount)", style: style, above: target)
            if let hit = renderer.headPosition(of: target) {
                let color = skill?.effectColor ?? (isCritical ? UIColor.systemYellow : UIColor(white: 1, alpha: 1))
                renderer.effects.burst(at: hit - [0, 0.5, 0], color: color, count: isCritical ? 26 : 12,
                                       speed: isCritical ? 2.4 : 1.6, size: 0.05, lifetime: 0.45, time: elapsed)
            }
            if target == me { feedback.hitsTaken += 1 }

        case let .heal(target, amount, skill):
            if amount > 0 { float("+\(amount)", style: .heal, above: target) }
            if skill == nil { renderer.sounds.play(.heal, from: renderer.entity(for: target), gain: -6) }

        case let .manaRestored(target, amount):
            if amount > 0 { float("+\(amount) MP", style: .mana, above: target) }
            renderer.sounds.play(.heal, from: renderer.entity(for: target), gain: -6)

        case let .skillCast(caster, skill, target):
            renderer.playCast(caster: caster, time: elapsed)
            playSkillEffect(skill, caster: caster, target: target)

        case let .skillFailed(caster, skill, reason):
            guard caster == me else { return }
            showToast(reason.message(for: skill))
            feedback.failures += 1
            renderer.sounds.playInterface(.error)

        case let .mobAbility(entity, ability):
            switch ability {
            case .hide:
                float("Hides!", style: .info, above: entity)
            case .charge:
                renderer.sounds.play(.windup, from: renderer.entity(for: entity))
                if host.currentSnapshot.entity(entity)?.target == me {
                    feedback.danger += 1
                    rumble.play(.danger)
                }
            case .split:
                renderer.sounds.play(.poof, from: renderer.entity(for: entity))
                if let position = renderer.renderedPosition(of: entity) {
                    let seeds = host.currentSnapshot.entity(entity)?.kind == .mob(.puffweed)
                    renderer.effects.burst(at: position + [0, seeds ? 1.4 : 0.6, 0], color: seeds ? Palette.puffWhite : Palette.sporeGlow,
                                           count: 50, speed: 2.5, size: 0.08, lifetime: 0.8, spread: 0.6, time: elapsed)
                }
            case .cloud:
                renderer.sounds.play(.hiss, from: renderer.entity(for: entity))
            case .swoop:
                renderer.sounds.play(.screech, from: renderer.entity(for: entity))
                if host.currentSnapshot.telegraphs.contains(where: { telegraph in
                    guard let me = host.currentSnapshot.entity(me) else { return false }
                    return telegraph.position.distance(to: me.position.xz) < GameSimulation.swoopRadius + 1
                }) {
                    feedback.danger += 1
                    rumble.play(.danger)
                }
            case .swoopImpact:
                renderer.sounds.play(.slam, from: renderer.entity(for: entity))
                if let position = renderer.renderedPosition(of: entity) {
                    let dust = UIColor(red: 0.75, green: 0.68, blue: 0.55, alpha: 1)
                    renderer.effects.shockwave(at: position, radius: GameSimulation.swoopRadius + 1, color: dust, duration: 0.5, time: elapsed)
                    renderer.effects.burst(at: position + [0, 0.5, 0], color: dust, count: 60, speed: 3,
                                           size: 0.15, lifetime: 1, rise: 0.5, spread: 1.5, time: elapsed)
                    shake(0.35)
                }
            case .gust:
                renderer.sounds.play(.whoosh, from: renderer.entity(for: entity), gain: 2)
            case .summon:
                renderer.sounds.play(.hoot, from: renderer.entity(for: entity), gain: 2)
                showToast("The owl calls for help!")
            case .enrage:
                renderer.sounds.play(.screech, from: renderer.entity(for: entity), gain: 4)
                showBanner(Banner(title: "The Hollow Owl is enraged!", subtitle: "Its attacks come faster"))
                if let position = renderer.renderedPosition(of: entity) {
                    renderer.effects.burst(at: position + [0, 4, 0], color: .systemRed, count: 80, speed: 3,
                                           size: 0.12, lifetime: 1.2, spread: 2, time: elapsed)
                }
            }

        case let .died(entity, killer):
            if entity == me {
                lastXPLost = 0 // the penalty, if any, arrives right after
                feedback.fainted += 1
                rumble.play(.heavy)
                requestSave()
            } else if let position = renderer.renderedPosition(of: entity) {
                renderer.sounds.play(.poof, from: renderer.entity(for: entity), gain: -4)
                renderer.effects.burst(at: position + [0, 0.3, 0], color: UIColor(red: 0.8, green: 0.7, blue: 0.5, alpha: 1),
                                       count: 24, speed: 1.2, size: 0.09, lifetime: 0.9, rise: 0.6, spread: 0.4, time: elapsed)
                if killer == me { feedback.kills += 1 }
            }

        case let .xpGained(player, amount):
            if player == me { float("+\(amount) XP", style: .xp, above: player) }

        case let .xpLost(player, amount):
            guard player == me else { return }
            lastXPLost = amount
            addFeed(symbol: "arrow.down.circle.fill", text: "Lost \(amount) XP", tint: .red)

        case let .blinked(player):
            renderer.sounds.play(.whoosh, from: renderer.entity(for: player), gain: -2)
            guard player == me else { return }
            addFeed(symbol: ItemID.blinkwing.symbol, text: "Back in Capstone Town", tint: ItemID.blinkwing.tint)
            requestSave()
            if let position = renderer.renderedPosition(of: player) {
                renderer.effects.burst(at: position + [0, 0.6, 0], color: UIColor(red: 0.75, green: 0.9, blue: 1, alpha: 1), count: 60,
                                       speed: 1.6, size: 0.06, lifetime: 1, rise: 1.5, spread: 0.5, time: elapsed)
            }

        case let .levelUp(player, level):
            renderer.playCheer(player, time: elapsed)
            guard player == me else { return }
            showBanner(Banner(title: "Level Up!", subtitle: "You are now level \(level) · +\(Attributes.pointsPerLevel) stat points"))
            addFeed(symbol: "plus.circle.fill", text: "Stat points to spend (\(statPointsHint))", tint: .mint)
            if level >= 10 { gameCenter.report(.level10) }
            if level >= 30 { gameCenter.report(.level30) }
            feedback.levelUps += 1
            renderer.sounds.playInterface(.levelUp, gain: 0)
            rumble.play(.celebrate)
            requestSave()
            if let position = renderer.renderedPosition(of: player) {
                let gold = UIColor(red: 1, green: 0.82, blue: 0.3, alpha: 1)
                renderer.effects.burst(at: position + [0, 0.2, 0], color: gold, count: 90, speed: 1.2,
                                       size: 0.07, lifetime: 1.6, rise: 2.5, spread: 0.6, time: elapsed)
                renderer.effects.shockwave(at: position, radius: 3, color: gold, duration: 0.7, time: elapsed)
                renderer.effects.pillar(at: position, color: gold, time: elapsed)
            }

        case .respawned:
            break

        case let .capsChanged(player, delta):
            guard player == me, delta > 0 else { return }
            addFeed(symbol: "circle.circle.fill", text: "+\(delta) caps", tint: .yellow)
            renderer.sounds.playInterface(.coin, gain: -8)
            requestSave()

        case let .itemReceived(player, item, count):
            guard player == me else { return }
            addFeed(symbol: item.symbol, text: count > 1 ? "\(item.definition.name) ×\(count)" : item.definition.name, tint: item.tint)
            feedback.loot += 1
            renderer.sounds.playInterface(.loot, gain: -6)
            requestSave()

        case let .itemUsed(player, _), let .equipmentChanged(player):
            if player == me { requestSave() }

        case let .upgradeAttempted(player, item, result):
            guard player == me else { return }
            showToast(result.message(for: item))
            requestSave()
            if result.succeeded {
                renderer.sounds.playInterface(.questDone, gain: -2)
                rumble.play(.light)
                if let position = renderer.renderedPosition(of: player) {
                    let amber = UIColor(red: 1, green: 0.7, blue: 0.25, alpha: 1)
                    renderer.effects.burst(at: position + [0, 0.6, 0], color: amber, count: 40, speed: 1.4,
                                           size: 0.05, lifetime: 0.9, rise: 1.5, spread: 0.3, time: elapsed)
                }
            } else {
                feedback.failures += 1
                renderer.sounds.playInterface(.error)
                rumble.play(result == .destroyed ? .heavy : .light)
            }

        case let .questAccepted(player, quest):
            guard player == me else { return }
            showBanner(Banner(title: "New Quest", subtitle: quest.definition.title))
            renderer.sounds.playInterface(.uiConfirm)
            requestSave()

        case let .questProgress(player, quest, progress, goal):
            guard player == me else { return }
            addFeed(symbol: progress >= goal ? "checkmark.seal.fill" : "scroll.fill",
                    text: "\(quest.definition.title) \(progress)/\(goal)", tint: progress >= goal ? .green : .orange)

        case let .questCompleted(player, quest):
            renderer.playCheer(player, time: elapsed)
            guard player == me else { return }
            showBanner(Banner(title: "Quest Complete", subtitle: quest.definition.title))
            if let next = quest.next?.definition {
                addFeed(symbol: next.giver.symbol, text: "Next: \(next.giver.definition.name) has a task for you", tint: .yellow)
            }
            feedback.levelUps += 1
            renderer.sounds.playInterface(.questDone, gain: 0)
            rumble.play(.celebrate)
            requestSave()

        case let .actionFailed(player, reason):
            guard player == me else { return }
            showToast(reason.message)
            feedback.failures += 1
            renderer.sounds.playInterface(.error)

        case let .classChosen(player, playerClass):
            renderer.playCheer(player, time: elapsed)
            guard player == me else { return }
            closePanel()
            showBanner(Banner(title: "You are now a \(playerClass.definition.name)", subtitle: playerClass.definition.role))
            gameCenter.report(.choseAPath)
            feedback.levelUps += 1
            renderer.sounds.playInterface(.classChosen, gain: 0)
            rumble.play(.celebrate)
            requestSave()
            if let position = renderer.renderedPosition(of: player) {
                let color = UIColor(playerClass.tint)
                renderer.effects.burst(at: position + [0, 0.5, 0], color: color, count: 120, speed: 1.6,
                                       size: 0.08, lifetime: 1.8, rise: 2, spread: 0.8, time: elapsed)
                renderer.effects.shockwave(at: position, radius: 4, color: color, duration: 0.9, time: elapsed)
            }

        case let .flightChanged(player, isFlying):
            renderer.sounds.play(isFlying ? .takeoff : .land, from: renderer.entity(for: player), gain: -2)
            if player == me, isFlying { gameCenter.report(.firstFlight) }
            if player == me, isFlying, let position = renderer.renderedPosition(of: player) {
                renderer.effects.burst(at: position + [0, 0.3, 0], color: UIColor(white: 1, alpha: 1), count: 40,
                                       speed: 1.5, size: 0.05, lifetime: 1, rise: 1, spread: 0.5, time: elapsed)
            }

        case let .worldBossSpawned(entity, kind):
            showBanner(Banner(title: "\(kind.displayName) has awoken!", subtitle: "It stirs in the Great Bough"))
            addFeed(symbol: "moon.stars.fill", text: "World event: \(kind.displayName)", tint: .indigo)
            renderer.sounds.playInterface(.horn, gain: 0)
            renderer.sounds.play(.hoot, from: renderer.entity(for: entity), gain: 6)
            rumble.play(.danger)

        case .worldBossDeparted:
            showBanner(Banner(title: "The Hollow Owl flies away", subtitle: "It will return another night"))
            renderer.sounds.playInterface(.whoosh, gain: -4)

        case let .worldBossDefeated(entity, participants):
            showBanner(Banner(title: "The Hollow Owl is defeated!",
                              subtitle: participants.count > 1 ? "\(participants.count) heroes share the spoils" : "The forest sleeps in peace"))
            renderer.sounds.playInterface(.questDone, gain: 2)
            rumble.play(.celebrate)
            if participants.contains(me) { gameCenter.report(.owlSlayer) }
            if let position = renderer.renderedPosition(of: entity) {
                let gold = UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
                renderer.effects.burst(at: position + [0, 3, 0], color: gold, count: 200, speed: 4,
                                       size: 0.12, lifetime: 2.2, rise: 1.5, spread: 2.5, time: elapsed)
                renderer.effects.shockwave(at: position, radius: 8, color: gold, duration: 1.2, time: elapsed)
            }
            requestSave()

        case let .blocked(source, target):
            renderer.playBlock(source: source, target: target, time: elapsed)
            renderer.sounds.play(.block, from: renderer.entity(for: target), gain: -2)
            float("Block", style: .info, above: target)
            if let hit = renderer.headPosition(of: target) {
                renderer.effects.burst(at: hit - [0, 0.6, 0], color: UIColor(red: 1, green: 0.9, blue: 0.6, alpha: 1), count: 10,
                                       speed: 1.8, size: 0.04, lifetime: 0.3, time: elapsed)
            }
            if target == me { rumble.play(.light) }

        case let .knockedBack(entity):
            if entity == me {
                rumble.play(.heavy)
                shake(0.2)
            }

        case let .petSummoned(player):
            guard player == me else { return }
            addFeed(symbol: "pawprint.fill", text: "\(petName) is following you", tint: Color(PetRig.tint))
            renderer.sounds.playInterface(.uiConfirm, gain: -6)
            requestSave()

        case let .petDismissed(player, reason):
            guard player == me else { return }
            switch reason {
            case .starving:
                showToast("\(petName) is starving and went home. Feed her Kibble!")
                feedback.failures += 1
                renderer.sounds.playInterface(.error)
            case .requested, .unslotted:
                addFeed(symbol: "house.fill", text: "\(petName) went home", tint: .secondary)
            }
            requestSave()

        case let .petFed(player, kibble):
            guard player == me else { return }
            addFeed(symbol: "pawprint.circle.fill", text: "\(petName) ate \(kibble) Kibble", tint: ItemID.kibble.tint)
            renderer.sounds.playInterface(.loot, gain: -6)
            if let position = renderer.petPosition(of: player) {
                renderer.effects.burst(at: position + [0, 0.5, 0], color: Palette.blush, count: 12, speed: 0.6,
                                       size: 0.06, lifetime: 0.8, rise: 1, time: elapsed)
            }
            requestSave()

        case let .petHungry(player):
            guard player == me else { return }
            showToast("\(petName) is hungry and slowing down")

        case let .petFetched(player):
            renderer.playPetFetch(owner: player, time: elapsed)

        case let .attributesChanged(player):
            guard player == me else { return }
            pendingPoints = Attributes()
            renderer.sounds.playInterface(.uiConfirm, gain: -4)
            requestSave()

        case let .materialsTraded(player, item, count, xp, _):
            guard player == me else { return }
            addFeed(symbol: NPCID.porcini.symbol, text: "Porcini took \(count) \(item.definition.name) (+\(xp) XP)", tint: item.tint)
            renderer.sounds.playInterface(.loot, gain: -4)
            requestSave()
        }
    }

    /// Where to open the character panel on the current device.
    private var statPointsHint: String {
        isGamepadConnected ? "open the bag, then LB/RB" : "T, or the person button"
    }

    /// The name of the pet in your slot ("Pip").
    private var petName: String {
        hud.player?.pet.slot?.definition.name ?? "Your pet"
    }

    /// P, or the pet slot in the bag: call your pet out or send it home.
    func togglePet() {
        guard let pet = hud.player?.pet, pet.slot != nil else {
            showToast(ActionFailure.noPet.message)
            return
        }
        host.send(pet.isSummoned || pet.awaitingFood ? .dismissPet : .summonPet)
    }

    /// Takes the pet out of its slot, back into the bag.
    func unslotPet() {
        host.send(.unslotPet)
    }

    private func playSkillEffect(_ skill: SkillID, caster: EntityID, target: EntityID?) {
        guard let casterPosition = renderer.renderedPosition(of: caster) else { return }
        let color = skill.effectColor
        switch skill.definition.effect {
        case .strike, .volley:
            renderer.sounds.play(.cast, from: renderer.entity(for: caster), gain: -4)
            if let target, let position = renderer.renderedPosition(of: target) {
                if skill.definition.range > 2, let from = renderer.headPosition(of: caster) {
                    renderer.effects.projectile(from: from - [0, 0.6, 0], to: position + [0, 0.5, 0], color: color, size: 0.16, time: elapsed)
                }
                renderer.effects.shockwave(at: position, radius: 1.4, color: color, duration: 0.3, time: elapsed)
            }
        case let .blast(radius, _):
            renderer.sounds.play(.cast, from: renderer.entity(for: caster), gain: -4)
            if let target, let position = renderer.renderedPosition(of: target) {
                renderer.sounds.play(.poof, from: renderer.entity(for: target), gain: -2)
                renderer.effects.shockwave(at: position, radius: radius, color: color, time: elapsed)
                renderer.effects.burst(at: position + [0, 0.4, 0], color: color, count: 70, speed: 3,
                                       size: 0.09, lifetime: 0.9, spread: 0.6, time: elapsed)
            }
        case .buff:
            renderer.sounds.play(.buff, from: renderer.entity(for: caster), gain: -4)
            renderer.effects.shockwave(at: casterPosition, radius: 1.6, color: color, duration: 0.6, time: elapsed)
            renderer.effects.burst(at: casterPosition + [0, 1, 0], color: color, count: 40, speed: 0.8,
                                   size: 0.06, lifetime: 1.2, rise: 1.2, spread: 0.6, time: elapsed)
        case let .burst(radius, _):
            renderer.sounds.play(.cast, from: renderer.entity(for: caster), gain: -4)
            renderer.effects.shockwave(at: casterPosition, radius: radius, color: color, time: elapsed)
            renderer.effects.burst(at: casterPosition + [0, 0.4, 0], color: color, count: 70, speed: 3.5,
                                   size: 0.08, lifetime: 0.8, spread: 0.5, time: elapsed)
        case .heal:
            renderer.sounds.play(.heal, from: renderer.entity(for: caster), gain: -4)
            renderer.effects.burst(at: casterPosition + [0, 0.3, 0], color: color, count: 50, speed: 0.6,
                                   size: 0.06, lifetime: 1.3, rise: 1.8, spread: 0.7, time: elapsed)
        }
    }

    private func float(_ text: String, style: FloatingText.Style, above id: EntityID) {
        guard var position = renderer.headPosition(of: id) else { return }
        nextID += 1
        // Spread stacked numbers a little so they don't overlap.
        position.x += Float(nextID % 5 - 2) * 0.12
        floatingTexts.append(FloatingText(id: nextID, text: text, style: style, worldPosition: position, born: elapsed))
        if floatingTexts.count > Self.maxFloatingTexts { floatingTexts.removeFirst(floatingTexts.count - Self.maxFloatingTexts) }
    }

    private func addFeed(symbol: String, text: String, tint: Color) {
        nextID += 1
        feed.append(FeedLine(id: nextID, symbol: symbol, text: text, tint: tint, expiry: elapsed + 4))
        if feed.count > 5 { feed.removeFirst(feed.count - 5) }
    }

    private func shake(_ strength: Float) {
        shakeStrength = strength
        shakeUntil = elapsed + 0.4
    }

    private func showToast(_ message: String) {
        toast = message
        toastExpiry = elapsed + 1.6
    }

    private func showBanner(_ banner: Banner) {
        self.banner = banner
        bannerExpiry = elapsed + 2.8
    }

    private func requestSave() {
        saveRequested = true
    }

    // MARK: - HUD

    private func updateHUD() {
        let snapshot = host.currentSnapshot
        // The snapshot only changes on sim ticks (20 Hz); skip the other frames.
        guard snapshot.tick != hudTick else { return }
        hudTick = snapshot.tick
        var state = HUDState(player: snapshot.viewer)
        if let viewer = snapshot.viewer, let targetID = viewer.target, let target = snapshot.entity(targetID) {
            state.target = TargetInfo(
                id: targetID, name: target.displayName, level: target.level,
                hp: target.hp, maxHP: target.maxHP,
                levelDelta: target.level - viewer.stats.level,
                isFightingYou: target.target == viewer.id, isAggressive: target.isAggressive)
        }
        if let bossID = host.simulation.worldBoss, let boss = snapshot.entity(bossID), boss.isAlive,
           let me = snapshot.entity(host.localPlayerID), boss.position.xz.distance(to: me.position.xz) < 45 {
            state.boss = BossInfo(id: bossID, name: boss.kind.displayName, hp: boss.hp, maxHP: boss.maxHP,
                                  isFighting: boss.target != nil)
        }
        if !state.matchesIgnoringCountdowns(hud) { hud = state }
        if state.isFainted != isFainted { isFainted = state.isFainted }
        let timers = HUDTimers(snapshot.viewer)
        if timers != self.timers { self.timers = timers }
    }

    private func updateFloatingTexts() {
        guard !floatingTexts.isEmpty else { return }
        floatingTexts = floatingTexts.compactMap { text in
            var text = text
            text.progress = (elapsed - text.born) / Self.floaterLifetime
            guard text.progress < 1 else { return nil }
            text.screenPosition = projector?.project(point: text.worldPosition, to: .global)
            return text
        }
    }

    /// Things that don't need to update every frame.
    private func updateSlowState(deltaTime: TimeInterval) {
        if toast != nil, elapsed > toastExpiry { toast = nil }
        if banner != nil, elapsed > bannerExpiry { banner = nil }
        if feed.contains(where: { $0.expiry < elapsed }) { feed.removeAll { $0.expiry < elapsed } }

        slowRefresh -= deltaTime
        guard slowRefresh <= 0 else { return }
        slowRefresh = 0.25

        let glyphs = input.glyphs
        if glyphs != self.glyphs { self.glyphs = glyphs }
        rumble.attach(to: input.controller)
        renderer.sounds.setBattleMusic(hud.boss?.isFighting == true, deltaTime: 0.25)
        renderer.sounds.setAmbience(night: renderer.atmosphere.nightFactor)
        let time = (host.currentSnapshot.timeOfDay * 96).rounded() / 96 // 15-minute steps
        if time != timeOfDay { timeOfDay = time }

        let snapshot = host.currentSnapshot
        if let me = snapshot.entity(host.localPlayerID) {
            let position = me.position.xz
            let zone = host.map.zone(at: position)
            if zone?.name != self.zone?.name {
                // Announce arrivals, MMO style (not on the first frame).
                if self.zone != nil, let zone {
                    let subtitle = zone.levels.map { "Level \($0.lowerBound)–\($0.upperBound)" } ?? "A safe place to rest"
                    showBanner(Banner(title: zone.name, subtitle: subtitle))
                }
                self.zone = zone
            }

            let nearby = me.isAlive ? host.map.npcs
                .filter { $0.position.distance(to: position) <= NPCID.interactionRange }
                .min { $0.position.distance(to: position) < $1.position.distance(to: position) }?.id : nil
            if nearby != nearbyNPC { nearbyNPC = nearby }
            if case let .npc(npc) = panel, npc != nearby { closePanel() }
        }
        renderer.updateQuestMarkers(questMarkers(for: snapshot.viewer))

        if saveRequested || elapsed > nextAutosave { saveNow() }

        #if DEBUG
        if let p = snapshot.entity(host.localPlayerID)?.position {
            let fps = deltaTime > 0 ? Int((1 / deltaTime).rounded()) : 0
            let text = String(format: "tick %llu · %.1f, %.1f · %d fps", snapshot.tick, p.x, p.z, fps)
            if text != debugText { debugText = text }
        }
        #endif
    }

    private func questMarkers(for viewer: PlayerStatus?) -> [NPCID: QuestMarker] {
        var markers: [NPCID: QuestMarker] = [:]
        for status in viewer?.quests ?? [] {
            let giver = status.id.definition.giver
            switch status.state {
            case .readyToTurnIn: markers[giver] = .turnIn
            case .available where markers[giver] != .turnIn: markers[giver] = .available
            default: break
            }
        }
        return markers
    }
}

#if DEBUG
/// Debug-only launch arguments for testing and screenshots:
/// `-autofight`, `-demo` (geared level 8 character), `-spawn village|lake|glade|maze|barkfall|fen|meadow|...`,
/// `-panel bag|stats|morel|shop|smith|truffle|porcini|map`, `-time 0...1` (0.5 = noon), `-level N`, `-class guardian|thornshot|sporecaster|dewkeeper`
/// (wielding the class weapon), `-weapon sword|axe|maul|bow|wand|staff` (plus a shield if one fits), `-owl` (summon the boss),
/// `-resetSave`. Anything but `-resetSave` uses a throwaway save.
private struct DebugLaunch {
    let arguments = ProcessInfo.processInfo.arguments

    var resetSave: Bool { arguments.contains("-resetSave") }
    var isThrowaway: Bool {
        ["-autofight", "-demo", "-spawn", "-panel", "-time", "-level", "-class", "-weapon", "-fly", "-owl", "-pet"].contains { arguments.contains($0) }
    }

    var timeOfDay: Float? { value(after: "-time").flatMap(Float.init) }

    func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    var profile: PlayerProfile? {
        let weapon = value(after: "-weapon").flatMap(WeaponType.init(rawValue:))
        let playerClass = value(after: "-class").flatMap(PlayerClass.init(rawValue:)) ?? weapon?.playerClass
        let level = value(after: "-level").flatMap(Int.init) ?? (playerClass != nil ? 18 : 10)
        guard arguments.contains("-demo") || playerClass != nil || weapon != nil || arguments.contains("-level") || arguments.contains("-fly")
                || arguments.contains("-pet")
        else { return nil }
        var bag = Inventory()
        bag.add(.dandelionSeed, count: 1)
        bag.add(.dewPotion, count: 8)
        bag.add(.nectarVial, count: 4)
        bag.add(.snailShell, count: 12)
        bag.add(.slugSlime, count: 3)
        bag.add(.beetleHorn, count: 2)
        bag.add(.thornRapier, count: 1)
        bag.add(.pebbleHatchet, count: 1)
        bag.add(.shellShield, count: 1)
        bag.add(.barkMail, count: 1)
        bag.add(.amberShard, count: 12)
        bag.add(.wardCharm, count: 2)
        bag.add(.dewleafGloves, count: 1)
        bag.add(.dewleafVest, count: 1)
        var equipment: [EquipSlot: Gear] = [.weapon: Gear(.twigSword, upgrade: 2), .hat: Gear(.dewleafCap), .body: Gear(.leafTunic),
                                            .gloves: Gear(.grassMitts), .boots: Gear(.dewleafSlippers, upgrade: 1)]
        // The best weapon of the asked-for family (or the class's own) that this level can wield.
        if let family = weapon ?? playerClass.flatMap({ job in WeaponType.allCases.first { $0.playerClass == job } }),
           let pick = ItemID.allCases.last(where: { $0.definition.weaponType == family && $0.definition.requiredLevel <= level }) {
            equipment[.weapon] = Gear(pick)
            if !family.isTwoHanded { equipment[.shield] = Gear(.barkBuckler) }
        }
        // `-pet [hungry]`: Pip out and following (optionally about to slow down), with Kibble to spare.
        var pet: PetProfile?
        if arguments.contains("-pet") {
            bag.add(.kibble, count: 60)
            let fullness = value(after: "-pet") == "hungry" ? GameSimulation.petHungryFullness + GameSimulation.tickRate * 5 : nil
            pet = PetProfile(slot: .pip, fullness: fullness.map { [.pup: $0] } ?? [:], summoned: true)
        }
        // Geared characters come with their stat points spent to suit them; `-level N` alone leaves them to spend.
        let points = Attributes.earned(atLevel: level)
        let attributes: Attributes? = switch playerClass {
        case .guardian: Attributes(strength: points / 3, stamina: points - points / 3)
        case .thornshot: Attributes(strength: points / 3, dexterity: points - points / 3)
        case .sporecaster: Attributes(stamina: points / 3, intelligence: points - points / 3)
        case .dewkeeper: Attributes(stamina: points / 2, intelligence: points - points / 2)
        case nil where arguments.contains("-demo") || weapon != nil: Attributes(strength: points / 2, stamina: points - points / 2)
        case nil: nil
        }
        return PlayerProfile(level: level, caps: 420, inventory: bag, equipment: equipment,
                             activeQuests: [.slipperySituation: 0], completedQuests: pet != nil ? [.shellShock, .aNoseForTrouble] : [.shellShock],
                             playerClass: playerClass, pet: pet, attributes: attributes)
    }

    var panel: Panel? {
        switch value(after: "-panel") {
        case "bag": .inventory
        case "morel": .npc(.elderMorel)
        case "shop": .npc(.chanterelle)
        case "smith": .npc(.shiitake)
        case "truffle": .npc(.truffle)
        case "porcini": .npc(.porcini)
        case "weapons": .npc(.oyster)
        case "armor": .npc(.enoki)
        case "board": .npc(.maitake)
        case "stats": .character
        case "map": .map
        default: nil
        }
    }

    func spawnPoint(in map: WorldMap) -> Vec2? {
        switch panel {
        case let .npc(npc): return map.placement(of: npc).map { $0.position + Vec2(0.6, 1.4) }
        default: break
        }
        let kind: MobKind? = switch value(after: "-spawn") ?? (arguments.contains("-autofight") ? "glade" : nil) {
        case "glade": .snail
        case "maze": .slug
        case "barkfall": .beetle
        case "fen": .sporeBeast
        case "meadow": .fuzzbee
        case "creek": .mossTurtle
        case "thicket": .weaverSpider
        case "rise": .hedgehog
        case "briars": .mantis
        case "grove": .stagBeetle
        default: nil
        }
        if value(after: "-spawn") == "village" { return map.playerSpawn }
        if value(after: "-spawn") == "lake", let lake = map.terrain.lakes.first {
            return lake.discs[0].center + Vec2(lake.discs[0].radius + 4, 0)
        }
        guard let kind, let area = map.mobSpawns.first(where: { $0.kind == kind }) else { return nil }
        return area.center + Vec2(-4, 4)
    }
}
#endif
