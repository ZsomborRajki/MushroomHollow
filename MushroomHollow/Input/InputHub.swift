import CoreGraphics
import GameController
import GameCore

/// One frame of player intent, merged from every input device.
struct InputFrame {
    /// Movement stick: x right, y forward, length <= 1.
    var move: SIMD2<Float> = .zero
    /// Camera turn this frame in radians: x > 0 turns right, y > 0 looks up.
    var look: SIMD2<Float> = .zero
    /// Camera zoom this frame in meters (positive = further away).
    var zoom: Float = 0
}

/// Merges game controllers, a hardware keyboard, and touch into an `InputFrame`.
/// Gameplay only ever sees `InputFrame`, never a device.
final class InputHub {
    // Touch state, written by the SwiftUI overlay.
    var touchMove: SIMD2<Float> = .zero
    private var pendingTouchLook: SIMD2<Float> = .zero
    private var pendingZoom: Float = 0

    static let stickLookSpeed: Float = 2.6 // rad/s at full deflection
    static let touchLookPerPoint: Float = 0.006
    static let stickDeadZone: Float = 0.12

    var isGamepadConnected: Bool {
        GCController.controllers().contains { $0.extendedGamepad != nil }
    }

    func addTouchLook(translation: CGSize) {
        pendingTouchLook += SIMD2(Float(translation.width), Float(-translation.height)) * Self.touchLookPerPoint
    }

    func addZoom(_ meters: Float) {
        pendingZoom += meters
    }

    func poll(deltaTime: Float) -> InputFrame {
        var frame = InputFrame()
        frame.move = touchMove
        frame.look = pendingTouchLook
        frame.zoom = pendingZoom
        pendingTouchLook = .zero
        pendingZoom = 0

        if let pad = GCController.current?.extendedGamepad ?? GCController.controllers().lazy.compactMap(\.extendedGamepad).first {
            let left = Self.deadZoned(SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value))
            let right = Self.deadZoned(SIMD2(pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value))
            frame.move += left
            frame.look += right * Self.stickLookSpeed * deltaTime
            if pad.dpad.up.isPressed { frame.zoom -= 8 * deltaTime }
            if pad.dpad.down.isPressed { frame.zoom += 8 * deltaTime }
        }

        if let keys = GCKeyboard.coalesced?.keyboardInput {
            func held(_ code: GCKeyCode) -> Bool { keys.button(forKeyCode: code)?.isPressed ?? false }
            var wasd = SIMD2<Float>.zero
            if held(.keyW) { wasd.y += 1 }
            if held(.keyS) { wasd.y -= 1 }
            if held(.keyD) { wasd.x += 1 }
            if held(.keyA) { wasd.x -= 1 }
            frame.move += wasd
            if held(.keyE) || held(.rightArrow) { frame.look.x += Self.stickLookSpeed * deltaTime }
            if held(.keyQ) || held(.leftArrow) { frame.look.x -= Self.stickLookSpeed * deltaTime }
            if held(.upArrow) { frame.look.y += Self.stickLookSpeed * 0.6 * deltaTime }
            if held(.downArrow) { frame.look.y -= Self.stickLookSpeed * 0.6 * deltaTime }
        }

        frame.move = frame.move.clampedLength(1)
        return frame
    }

    /// Radial dead zone, rescaled so movement starts smoothly from zero.
    private static func deadZoned(_ stick: SIMD2<Float>) -> SIMD2<Float> {
        let length = stick.length
        guard length > stickDeadZone else { return .zero }
        let scaled = min((length - stickDeadZone) / (1 - stickDeadZone), 1)
        return stick / length * scaled
    }
}
