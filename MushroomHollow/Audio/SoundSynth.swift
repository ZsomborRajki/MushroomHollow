import Foundation

/// Every sound in the game, synthesized at launch (no audio assets yet).
nonisolated enum Sound: CaseIterable, Sendable {
    case swing, hit, crit, hurt, block
    case cast, heal, buff, shoot
    case levelUp, questDone, classChosen
    case coin, loot
    case uiMove, uiConfirm, error
    case poof, windup, whoosh, hiss
    case takeoff, land
    case hoot, screech, horn, slam
    case ambienceDay, ambienceNight, bossTheme

    var isLooping: Bool { self == .ambienceDay || self == .ambienceNight || self == .bossTheme }
}

/// A tiny offline synthesizer: oscillators, noise, envelopes, and a one-pole filter.
nonisolated enum SoundSynth {
    static let sampleRate = 22_050.0

    static func wav(for sound: Sound) -> Data {
        encodeWAV(render(sound))
    }

    // MARK: - Sound design

    private static func render(_ sound: Sound) -> [Float] {
        switch sound {
        case .swing:
            return sweepNoise(duration: 0.16, from: 700, to: 3200, volume: 0.35, decay: 18)
        case .hit:
            return mix(
                tone(duration: 0.16, volume: 0.8, decay: 26) { t in 55 + 150 * exp(-t * 18) },
                sweepNoise(duration: 0.1, from: 1800, to: 400, volume: 0.35, decay: 35))
        case .crit:
            return mix(
                tone(duration: 0.2, volume: 0.9, decay: 20) { t in 60 + 190 * exp(-t * 16) },
                tone(duration: 0.12, volume: 0.35, decay: 30, shape: .square) { _ in 1400 },
                sweepNoise(duration: 0.12, from: 3000, to: 600, volume: 0.35, decay: 30))
        case .hurt:
            return mix(
                tone(duration: 0.2, volume: 0.7, decay: 18) { t in 60 + 60 * exp(-t * 10) },
                sweepNoise(duration: 0.12, from: 900, to: 200, volume: 0.3, decay: 25))
        case .block:
            // A hollow wooden clonk.
            return mix(
                tone(duration: 0.16, volume: 0.7, decay: 28) { t in 330 - t * 700 },
                tone(duration: 0.08, volume: 0.2, decay: 45, shape: .square) { _ in 950 },
                sweepNoise(duration: 0.08, from: 2600, to: 900, volume: 0.25, decay: 40))
        case .cast:
            return arpeggio([880, 1108.7, 1318.5], step: 0.06, tail: 0.25, volume: 0.35)
        case .heal:
            return tone(duration: 0.55, volume: 0.35, envelope: .swell) { t in 523 + 523 * t / 0.55 + sin(t * 38) * 12 }
        case .buff:
            return mix(
                arpeggio([659.3, 830.6, 987.8, 1318.5], step: 0.05, tail: 0.35, volume: 0.3),
                tone(duration: 0.5, volume: 0.15, envelope: .swell) { _ in 329.6 })
        case .shoot:
            return mix(
                sweepNoise(duration: 0.12, from: 4000, to: 1500, volume: 0.3, decay: 30),
                tone(duration: 0.08, volume: 0.25, decay: 40) { t in 900 - t * 4000 })
        case .levelUp:
            return mix(
                arpeggio([523.25, 659.25, 783.99, 1046.5], step: 0.09, tail: 0.05, volume: 0.4),
                delayed(0.36, chord([523.25, 659.25, 783.99, 1046.5], duration: 0.9, volume: 0.35)))
        case .questDone:
            return mix(
                arpeggio([783.99, 1046.5, 1318.5, 1568], step: 0.08, tail: 0.05, volume: 0.35),
                delayed(0.32, chord([783.99, 987.77, 1174.66, 1568], duration: 0.8, volume: 0.3)))
        case .classChosen:
            return mix(
                chord([261.63, 392, 523.25], duration: 1.4, volume: 0.35),
                delayed(0.2, arpeggio([783.99, 1046.5, 1318.5, 1568, 2093], step: 0.07, tail: 0.5, volume: 0.25)))
        case .coin:
            return mix(
                tone(duration: 0.08, volume: 0.35, decay: 30) { _ in 1318.5 },
                delayed(0.06, tone(duration: 0.25, volume: 0.35, decay: 14) { _ in 1760 }))
        case .loot:
            return tone(duration: 0.09, volume: 0.4, decay: 30) { t in 500 + t * 5000 }
        case .uiMove:
            return tone(duration: 0.03, volume: 0.18, decay: 120) { _ in 1900 }
        case .uiConfirm:
            return mix(
                tone(duration: 0.05, volume: 0.3, decay: 60) { _ in 880 },
                delayed(0.05, tone(duration: 0.08, volume: 0.3, decay: 40) { _ in 1320 }))
        case .error:
            return mix(
                tone(duration: 0.08, volume: 0.22, envelope: .flat, shape: .square) { _ in 170 },
                delayed(0.12, tone(duration: 0.08, volume: 0.22, envelope: .flat, shape: .square) { _ in 150 }))
        case .poof:
            return sweepNoise(duration: 0.4, from: 2200, to: 180, volume: 0.5, decay: 9)
        case .windup:
            return tone(duration: 0.8, volume: 0.28, envelope: .rise, shape: .saw) { t in 70 + 140 * t / 0.8 }
                .enumerated().map { index, sample in sample * Float(0.6 + 0.4 * sin(Double(index) / sampleRate * 2 * .pi * 25)) }
        case .whoosh:
            return sweepNoise(duration: 0.5, from: 300, to: 2500, volume: 0.45, envelope: .swell)
        case .hiss:
            return highpass(noise(duration: 0.8, volume: 0.3, envelope: .swell), amount: 0.9)
        case .takeoff:
            return mix(
                sweepNoise(duration: 0.7, from: 400, to: 3000, volume: 0.35, envelope: .swell),
                tone(duration: 0.7, volume: 0.18, envelope: .swell) { t in 300 + 500 * t / 0.7 })
        case .land:
            return mix(
                sweepNoise(duration: 0.3, from: 1500, to: 200, volume: 0.35, decay: 12),
                tone(duration: 0.15, volume: 0.35, decay: 25) { t in 90 - t * 200 })
        case .hoot:
            // "Hoo... hoo-hoo", low and breathy.
            let hoo = { (pitch: Double, length: Double) in
                mix(tone(duration: length, volume: 0.45, envelope: .swell) { t in pitch - t * 30 + sin(t * 30) * 3 },
                    lowpass(noise(duration: length, volume: 0.08, envelope: .swell), cutoff: 600))
            }
            var out = hoo(330, 0.5)
            add(hoo(300, 0.25), into: &out, at: 0.75)
            add(hoo(290, 0.4), into: &out, at: 1.05)
            return out
        case .screech:
            return mix(
                tone(duration: 0.7, volume: 0.25, envelope: .swell, shape: .saw) { t in 2100 - t * 1500 + sin(t * 70) * 60 },
                highpass(noise(duration: 0.7, volume: 0.25, envelope: .swell), amount: 0.9))
        case .horn:
            // A distant warning horn for world events.
            return mix(
                tone(duration: 2.2, volume: 0.35, envelope: .swell, shape: .saw) { _ in 110 },
                tone(duration: 2.2, volume: 0.25, envelope: .swell, shape: .saw) { _ in 164.8 },
                tone(duration: 2.2, volume: 0.2, envelope: .swell) { _ in 220 })
                .map { $0 * 0.8 }
        case .slam:
            return mix(
                tone(duration: 0.6, volume: 0.9, decay: 7) { t in 40 + 70 * exp(-t * 9) },
                sweepNoise(duration: 0.5, from: 1500, to: 120, volume: 0.6, decay: 8))
        case .bossTheme:
            return bossTheme()
        case .ambienceDay:
            return dayAmbience()
        case .ambienceNight:
            return nightAmbience()
        }
    }

    private static func dayAmbience() -> [Float] {
        let duration = 8.0
        var out = lowpass(noise(duration: duration, volume: 0.35, envelope: .flat), cutoff: 350)
        for i in out.indices {
            // Two slow gusts per loop, so the loop point is seamless.
            let t = Double(i) / sampleRate
            out[i] *= Float(0.55 + 0.45 * sin(t / duration * 2 * .pi * 2))
        }
        // A few birds.
        for (start, pitch) in [(0.7, 3100.0), (1.0, 3400.0), (3.2, 2700.0), (5.4, 3600.0), (5.65, 3300.0), (6.8, 2900.0)] {
            for chirp in 0..<3 {
                let when = start + Double(chirp) * 0.09
                let bird = tone(duration: 0.07, volume: 0.12, envelope: .swell) { t in pitch + t * 9000 }
                add(bird, into: &out, at: when)
            }
        }
        return out
    }

    /// An 8-bar loop: pounding drums, a minor bass line, and a tense pulse on top.
    private static func bossTheme() -> [Float] {
        let beat = 60.0 / 132
        let bars = 4
        let duration = beat * 4 * Double(bars)
        var out = [Float](repeating: 0, count: Int(duration * sampleRate))
        let kick = tone(duration: 0.3, volume: 0.7, decay: 14) { t in 45 + 90 * exp(-t * 30) }
        let snare = sweepNoise(duration: 0.18, from: 5000, to: 1500, volume: 0.35, decay: 22)
        // A minor: A2, C3, E3, G2 roots per bar.
        let roots: [Double] = [110, 130.8, 164.8, 98]
        for step in 0..<(bars * 8) {
            let when = Double(step) * beat / 2
            if step % 4 == 0 || step % 8 == 3 { add(kick, into: &out, at: when) }
            if step % 4 == 2 { add(snare, into: &out, at: when) }
            let root = roots[step / 8]
            add(tone(duration: beat / 2, volume: 0.28, decay: 6, shape: .saw) { _ in root / 2 }, into: &out, at: when)
            // Staccato pulse, an octave and a fifth up.
            let pulse = step % 2 == 0 ? root * 2 : root * 3
            add(tone(duration: beat / 4, volume: 0.1, decay: 20, shape: .square) { _ in pulse }, into: &out, at: when)
        }
        return Array(out.prefix(Int(duration * sampleRate)))
    }

    private static func nightAmbience() -> [Float] {
        let duration = 6.0
        var out = lowpass(noise(duration: duration, volume: 0.18, envelope: .flat), cutoff: 250)
        // Two crickets, trilling at slightly different rates.
        for (pitch, period, offset) in [(4300.0, 0.75, 0.0), (4700.0, 1.0, 0.35)] {
            var when = offset
            while when + 0.3 < duration {
                let trill = tone(duration: 0.28, volume: 0.07, envelope: .flat) { _ in pitch }
                    .enumerated().map { index, sample in
                        sample * Float(max(0, sin(Double(index) / sampleRate * 2 * .pi * 32)))
                    }
                add(trill, into: &out, at: when)
                when += period
            }
        }
        return out
    }

    // MARK: - Building blocks

    enum Shape { case sine, square, saw }
    enum Envelope { case decay(Double), swell, rise, flat }

    private static func tone(duration: Double, volume: Float, decay: Double, shape: Shape = .sine,
                             frequency: (Double) -> Double) -> [Float] {
        tone(duration: duration, volume: volume, envelope: .decay(decay), shape: shape, frequency: frequency)
    }

    private static func tone(duration: Double, volume: Float, envelope: Envelope, shape: Shape = .sine,
                             frequency: (Double) -> Double) -> [Float] {
        let count = Int(duration * sampleRate)
        var phase = 0.0
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            phase += frequency(t) / sampleRate
            let cycle = phase - floor(phase)
            let wave: Double = switch shape {
            case .sine: sin(cycle * 2 * .pi) + 0.15 * sin(cycle * 6 * .pi)
            case .square: cycle < 0.5 ? 0.6 : -0.6
            case .saw: cycle * 1.2 - 0.6
            }
            return Float(wave) * volume * gain(envelope, t, duration)
        }
    }

    private static func noise(duration: Double, volume: Float, envelope: Envelope) -> [Float] {
        var seed: UInt32 = 0x1234_5678
        let count = Int(duration * sampleRate)
        return (0..<count).map { i in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let white = Float(seed >> 8) / Float(1 << 24) * 2 - 1
            return white * volume * gain(envelope, Double(i) / sampleRate, duration)
        }
    }

    /// Noise through a lowpass whose cutoff glides from `from` to `to` Hz.
    private static func sweepNoise(duration: Double, from: Double, to: Double, volume: Float, decay: Double) -> [Float] {
        sweepNoise(duration: duration, from: from, to: to, volume: volume, envelope: .decay(decay))
    }

    private static func sweepNoise(duration: Double, from: Double, to: Double, volume: Float, envelope: Envelope) -> [Float] {
        let raw = noise(duration: duration, volume: volume * 1.6, envelope: envelope)
        var state: Float = 0
        return raw.enumerated().map { i, sample in
            let t = Double(i) / sampleRate / duration
            let cutoff = from * pow(to / from, t)
            let alpha = Float(1 - exp(-2 * .pi * cutoff / sampleRate))
            state += alpha * (sample - state)
            return state
        }
    }

    private static func lowpass(_ input: [Float], cutoff: Double) -> [Float] {
        let alpha = Float(1 - exp(-2 * .pi * cutoff / sampleRate))
        var state: Float = 0
        return input.map { sample in
            state += alpha * (sample - state)
            return state * 2.5
        }
    }

    private static func highpass(_ input: [Float], amount: Float) -> [Float] {
        let low = lowpass(input, cutoff: 1200)
        return zip(input, low).map { $0 - $1 / 2.5 * amount }
    }

    private static func gain(_ envelope: Envelope, _ t: Double, _ duration: Double) -> Float {
        let attack = min(1, t / 0.004) // tiny attack avoids clicks
        let release = min(1, (duration - t) / 0.01)
        let shape: Double = switch envelope {
        case let .decay(rate): exp(-t * rate)
        case .swell: sin(.pi * t / duration)
        case .rise: t / duration
        case .flat: 1
        }
        return Float(attack * release * shape)
    }

    private static func arpeggio(_ notes: [Double], step: Double, tail: Double, volume: Float) -> [Float] {
        var out: [Float] = []
        for (index, note) in notes.enumerated() {
            let length = index == notes.count - 1 ? step + tail : step * 1.8
            add(tone(duration: length, volume: volume, decay: 9) { _ in note }, into: &out, at: Double(index) * step)
        }
        return out
    }

    private static func chord(_ notes: [Double], duration: Double, volume: Float) -> [Float] {
        mix(notes.map { note in tone(duration: duration, volume: volume / Float(notes.count) * 1.6, decay: 3.5) { _ in note } })
    }

    private static func delayed(_ seconds: Double, _ samples: [Float]) -> [Float] {
        Array(repeating: 0, count: Int(seconds * sampleRate)) + samples
    }

    private static func mix(_ parts: [Float]...) -> [Float] {
        mix(parts)
    }

    private static func mix(_ parts: [[Float]]) -> [Float] {
        var out = [Float](repeating: 0, count: parts.map(\.count).max() ?? 0)
        for part in parts {
            for (i, sample) in part.enumerated() { out[i] += sample }
        }
        return out
    }

    private static func add(_ part: [Float], into out: inout [Float], at seconds: Double) {
        let start = Int(seconds * sampleRate)
        if out.count < start + part.count { out += [Float](repeating: 0, count: start + part.count - out.count) }
        for (i, sample) in part.enumerated() { out[start + i] += sample }
    }

    // MARK: - WAV

    private static func encodeWAV(_ samples: [Float]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let rate = UInt32(sampleRate)
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)) // PCM, mono
        append(rate); append(rate * 2)
        append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        for sample in samples {
            append(Int16(max(-1, min(1, sample)) * Float(Int16.max)))
        }
        return data
    }
}
