import CoreGraphics
import GameController
import GameCore

/// Navigation inside an open panel (controller / keyboard).
enum MenuInput: Equatable {
    case up, down, left, right
    case confirm, back
    case previousTab, nextTab
}

/// Discrete things the player asked for this frame (button presses, taps).
enum InputAction: Equatable {
    /// Attack the current/nearest target, talk to a nearby NPC, or get up after fainting.
    case primary
    case cycleTarget(Int)
    case clearTarget
    /// Index into the skill bar.
    case skill(Int)
    /// Tapped a specific entity in the world.
    case select(EntityID)
    case toggleInventory
    /// 0 = HP potion, 1 = MP potion.
    case quickItem(Int)
    case toggleFlight
    case menu(MenuInput)
}

/// One frame of player intent, merged from every input device.
struct InputFrame {
    /// Movement stick: x right, y forward, length <= 1.
    var move: SIMD2<Float> = .zero
    /// Camera turn this frame in radians: x > 0 turns right, y > 0 looks up.
    var look: SIMD2<Float> = .zero
    /// Camera zoom this frame in meters (positive = further away).
    var zoom: Float = 0
    /// While flying: -1 (descend) ... 1 (climb).
    var climb: Float = 0
    var actions: [InputAction] = []
}

/// SF Symbols for the connected controller's buttons, so prompts match the pad in hand
/// (A/B/X/Y on Xbox, shapes on PlayStation...).
struct ControllerGlyphs: Equatable {
    var primary = "a.circle"
    var back = "b.circle"
    /// Base skills on X / Y / B, class skills on RT + X / RT + Y.
    var skills = ["x.circle", "y.circle", "b.circle", "x.circle", "y.circle"]
    var shift = "rt.rectangle.roundedtop"
    var flight = "l.joystick.press.down"
    var previousTarget = "lb.rectangle.roundedbottom"
    var nextTarget = "rb.rectangle.roundedbottom"
    var menu = "line.3.horizontal.circle"
    var quickItems = ["dpad.left.filled", "dpad.right.filled"]
}

/// Merges game controllers, a hardware keyboard, and touch into an `InputFrame`.
/// Gameplay only ever sees `InputFrame`, never a device.
final class InputHub {
    // Touch state, written by the SwiftUI overlay.
    var touchMove: SIMD2<Float> = .zero
    var touchClimb: Float = 0
    private var pendingTouchLook: SIMD2<Float> = .zero
    private var pendingZoom: Float = 0
    private var queuedActions: [InputAction] = []
    /// Buttons held last frame, for press edge detection.
    private var held: Set<String> = []

    static let stickLookSpeed: Float = 2.6 // rad/s at full deflection
    static let touchLookPerPoint: Float = 0.006
    static let stickDeadZone: Float = 0.12

    private var gamepad: GCExtendedGamepad? {
        GCController.current?.extendedGamepad ?? GCController.controllers().lazy.compactMap(\.extendedGamepad).first
    }

    var isGamepadConnected: Bool { gamepad != nil }

    var controller: GCController? {
        GCController.current ?? GCController.controllers().first { $0.extendedGamepad != nil }
    }

    var glyphs: ControllerGlyphs? {
        guard let pad = gamepad else { return nil }
        var glyphs = ControllerGlyphs()
        glyphs.primary = pad.buttonA.sfSymbolsName ?? glyphs.primary
        glyphs.back = pad.buttonB.sfSymbolsName ?? glyphs.back
        glyphs.skills = [pad.buttonX, pad.buttonY, pad.buttonB, pad.buttonX, pad.buttonY].enumerated().map { index, button in
            button.sfSymbolsName ?? glyphs.skills[index]
        }
        glyphs.shift = pad.rightTrigger.sfSymbolsName ?? glyphs.shift
        glyphs.flight = pad.leftThumbstickButton?.sfSymbolsName ?? glyphs.flight
        glyphs.previousTarget = pad.leftShoulder.sfSymbolsName ?? glyphs.previousTarget
        glyphs.nextTarget = pad.rightShoulder.sfSymbolsName ?? glyphs.nextTarget
        glyphs.menu = pad.buttonMenu.sfSymbolsName ?? glyphs.menu
        return glyphs
    }

    func addTouchLook(translation: CGSize) {
        pendingTouchLook += SIMD2(Float(translation.width), Float(-translation.height)) * Self.touchLookPerPoint
    }

    func addZoom(_ meters: Float) {
        pendingZoom += meters
    }

    /// Touch buttons and taps feed actions in here.
    func enqueue(_ action: InputAction) {
        queuedActions.append(action)
    }

    /// `menuOpen` switches buttons from gameplay meanings to panel navigation;
    /// `flying` turns the triggers into climb/descend.
    func poll(deltaTime: Float, menuOpen: Bool, flying: Bool) -> InputFrame {
        var frame = InputFrame()
        var actions = queuedActions
        queuedActions.removeAll()
        var pressedNow: Set<String> = []
        func button(_ name: String, _ isPressed: Bool, _ action: InputAction) {
            guard isPressed else { return }
            pressedNow.insert(name)
            if !held.contains(name) { actions.append(action) }
        }

        if menuOpen {
            pendingTouchLook = .zero
            pendingZoom = 0
            pollMenu(button)
        } else {
            frame.move = touchMove
            frame.look = pendingTouchLook
            frame.zoom = pendingZoom
            frame.climb = touchClimb
            pendingTouchLook = .zero
            pendingZoom = 0
            pollGameplay(&frame, deltaTime: deltaTime, flying: flying, button)
        }

        held = pressedNow
        frame.actions = actions
        frame.move = frame.move.clampedLength(1)
        return frame
    }

    private func pollGameplay(_ frame: inout InputFrame, deltaTime: Float, flying: Bool, _ button: (String, Bool, InputAction) -> Void) {
        if let pad = gamepad {
            let left = Self.deadZoned(SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value))
            let right = Self.deadZoned(SIMD2(pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value))
            frame.move += left
            frame.look += right * Self.stickLookSpeed * deltaTime
            if pad.dpad.up.isPressed { frame.zoom -= 8 * deltaTime }
            if pad.dpad.down.isPressed { frame.zoom += 8 * deltaTime }

            // RT is a shift for class skills on the ground, and climb in the air.
            let shifted = !flying && pad.rightTrigger.isPressed
            if flying { frame.climb += pad.rightTrigger.value - pad.leftTrigger.value }
            button("pad.a", pad.buttonA.isPressed, .primary)
            button("pad.x", pad.buttonX.isPressed, .skill(shifted ? 3 : 0))
            button("pad.y", pad.buttonY.isPressed, .skill(shifted ? 4 : 1))
            button("pad.b", pad.buttonB.isPressed, .skill(2))
            button("pad.lb", pad.leftShoulder.isPressed, .cycleTarget(-1))
            button("pad.rb", pad.rightShoulder.isPressed, .cycleTarget(1))
            button("pad.lt", !flying && pad.leftTrigger.isPressed, .clearTarget)
            button("pad.l3", pad.leftThumbstickButton?.isPressed ?? false, .toggleFlight)
            button("pad.left", pad.dpad.left.isPressed, .quickItem(0))
            button("pad.right", pad.dpad.right.isPressed, .quickItem(1))
            button("pad.menu", pad.buttonMenu.isPressed, .toggleInventory)
        }

        if let keys = GCKeyboard.coalesced?.keyboardInput {
            func down(_ code: GCKeyCode) -> Bool { keys.button(forKeyCode: code)?.isPressed ?? false }
            var wasd = SIMD2<Float>.zero
            if down(.keyW) { wasd.y += 1 }
            if down(.keyS) { wasd.y -= 1 }
            if down(.keyD) { wasd.x += 1 }
            if down(.keyA) { wasd.x -= 1 }
            frame.move += wasd
            if down(.keyE) || down(.rightArrow) { frame.look.x += Self.stickLookSpeed * deltaTime }
            if down(.keyQ) || down(.leftArrow) { frame.look.x -= Self.stickLookSpeed * deltaTime }
            if down(.upArrow) { frame.look.y += Self.stickLookSpeed * 0.6 * deltaTime }
            if down(.downArrow) { frame.look.y -= Self.stickLookSpeed * 0.6 * deltaTime }

            button("key.space", down(.spacebar) || down(.keyF), .primary)
            button("key.tab", down(.tab), .cycleTarget(1))
            button("key.esc", down(.escape), .clearTarget)
            button("key.1", down(.one), .skill(0))
            button("key.2", down(.two), .skill(1))
            button("key.3", down(.three), .skill(2))
            button("key.4", down(.four), .skill(3))
            button("key.5", down(.five), .skill(4))
            button("key.6", down(.six), .quickItem(0))
            button("key.7", down(.seven), .quickItem(1))
            button("key.i", down(.keyI), .toggleInventory)
            button("key.g", down(.keyG), .toggleFlight)
            if down(.keyR) { frame.climb += 1 }
            if down(.keyC) { frame.climb -= 1 }
        }
        frame.climb = max(-1, min(1, frame.climb))
    }

    private func pollMenu(_ button: (String, Bool, InputAction) -> Void) {
        if let pad = gamepad {
            let stick = SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value)
            let horizontal = abs(stick.x) > abs(stick.y)
            button("menu.up", pad.dpad.up.isPressed || (!horizontal && stick.y > 0.6), .menu(.up))
            button("menu.down", pad.dpad.down.isPressed || (!horizontal && stick.y < -0.6), .menu(.down))
            button("menu.left", pad.dpad.left.isPressed || (horizontal && stick.x < -0.6), .menu(.left))
            button("menu.right", pad.dpad.right.isPressed || (horizontal && stick.x > 0.6), .menu(.right))
            button("pad.a", pad.buttonA.isPressed, .menu(.confirm))
            button("pad.b", pad.buttonB.isPressed, .menu(.back))
            button("pad.lb", pad.leftShoulder.isPressed, .menu(.previousTab))
            button("pad.rb", pad.rightShoulder.isPressed, .menu(.nextTab))
            button("pad.menu", pad.buttonMenu.isPressed, .toggleInventory)
        }

        if let keys = GCKeyboard.coalesced?.keyboardInput {
            func down(_ code: GCKeyCode) -> Bool { keys.button(forKeyCode: code)?.isPressed ?? false }
            button("key.up", down(.upArrow) || down(.keyW), .menu(.up))
            button("key.down", down(.downArrow) || down(.keyS), .menu(.down))
            button("key.left", down(.leftArrow) || down(.keyA), .menu(.left))
            button("key.right", down(.rightArrow) || down(.keyD), .menu(.right))
            button("key.space", down(.spacebar) || down(.returnOrEnter) || down(.keyF), .menu(.confirm))
            button("key.esc", down(.escape) || down(.deleteOrBackspace), .menu(.back))
            button("key.q", down(.keyQ), .menu(.previousTab))
            button("key.e", down(.keyE), .menu(.nextTab))
            button("key.i", down(.keyI), .toggleInventory)
        }
    }

    /// Radial dead zone, rescaled so movement starts smoothly from zero.
    private static func deadZoned(_ stick: SIMD2<Float>) -> SIMD2<Float> {
        let length = stick.length
        guard length > stickDeadZone else { return .zero }
        let scaled = min((length - stickDeadZone) / (1 - stickDeadZone), 1)
        return stick / length * scaled
    }
}
