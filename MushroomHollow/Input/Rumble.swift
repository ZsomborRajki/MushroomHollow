import CoreHaptics
import GameController

/// Game controller rumble via Core Haptics (the phone itself uses SwiftUI's sensoryFeedback).
final class Rumble {
    enum Pulse {
        case light, heavy, danger, celebrate
    }

    private var engine: CHHapticEngine?
    private weak var controller: GCController?
    /// Patterns are fixed, so build each once (combat plays them several times a second).
    private var patterns: [Pulse: CHHapticPattern] = [:]

    /// Call when the active controller may have changed.
    func attach(to controller: GCController?) {
        guard controller !== self.controller else { return }
        self.controller = controller
        engine?.stop()
        engine = controller?.haptics?.createEngine(withLocality: .default)
        engine?.playsHapticsOnly = true
        try? engine?.start()
    }

    func play(_ pulse: Pulse) {
        guard let engine, let pattern = pattern(for: pulse),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    private func pattern(for pulse: Pulse) -> CHHapticPattern? {
        if let cached = patterns[pulse] { return cached }
        let events: [CHHapticEvent] = switch pulse {
        case .light:
            [transient(intensity: 0.45, sharpness: 0.6, at: 0)]
        case .heavy:
            [transient(intensity: 1, sharpness: 0.3, at: 0), transient(intensity: 0.6, sharpness: 0.2, at: 0.07)]
        case .danger:
            [continuous(intensity: 0.5, sharpness: 0.8, at: 0, duration: 0.25)]
        case .celebrate:
            [transient(intensity: 0.6, sharpness: 0.7, at: 0), transient(intensity: 0.8, sharpness: 0.7, at: 0.12),
             continuous(intensity: 0.7, sharpness: 0.4, at: 0.24, duration: 0.4)]
        }
        let pattern = try? CHHapticPattern(events: events, parameters: [])
        patterns[pulse] = pattern
        return pattern
    }

    private func transient(intensity: Float, sharpness: Float, at time: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time)
    }

    private func continuous(intensity: Float, sharpness: Float, at time: TimeInterval, duration: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time, duration: duration)
    }
}
