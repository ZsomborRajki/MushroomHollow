import RealityKit

/// Loads the synthesized sounds into RealityKit and plays them: combat sounds come from
/// the entity that made them (spatial audio), UI sounds and ambience are non-spatial.
@MainActor
final class SoundBank {
    let root = Entity()
    private let interface = Entity()
    private let dayAmbience = Entity()
    private let nightAmbience = Entity()
    private let music = Entity()
    private var musicController: AudioPlaybackController?
    private var musicLevel: Float = 0
    private var resources: [Sound: AudioFileResource] = [:]
    private var dayController: AudioPlaybackController?
    private var nightController: AudioPlaybackController?
    private var lastNight: Float = -1
    /// Silences everything: one-shots are skipped, loops held at silence.
    var isMuted = false {
        didSet { updateLoops() }
    }

    init() {
        for entity in [interface, dayAmbience, nightAmbience, music] {
            entity.components.set(AmbientAudioComponent())
            root.addChild(entity)
        }
    }

    /// Synthesizes everything off the main actor, then builds the audio resources.
    func load() async {
        let rendered = await Task.detached(priority: .utility) {
            Sound.allCases.map { ($0, SoundSynth.wav(for: $0)) }
        }.value
        for (sound, data) in rendered {
            let configuration = AudioFileResource.Configuration(shouldLoop: sound.isLooping)
            resources[sound] = try? await AudioFileResource(from: data, configuration: configuration)
        }
        if let day = resources[.ambienceDay] { dayController = dayAmbience.playAudio(day) }
        if let night = resources[.ambienceNight] { nightController = nightAmbience.playAudio(night) }
        if let theme = resources[.bossTheme] {
            musicController = music.playAudio(theme)
        }
        setAmbience(night: max(lastNight, 0), force: true)
    }

    /// Plays a sound from an entity in the world, so it pans and fades with distance.
    func play(_ sound: Sound, from entity: Entity?, gain: Double = 0) {
        guard !isMuted, let resource = resources[sound] else { return }
        guard let entity else { return playInterface(sound, gain: gain) }
        if entity.components[SpatialAudioComponent.self] == nil {
            entity.components.set(SpatialAudioComponent(gain: 0, directivity: .beam(focus: 0)))
        }
        entity.playAudio(resource).gain = gain
    }

    func playInterface(_ sound: Sound, gain: Double = -4) {
        guard !isMuted, let resource = resources[sound] else { return }
        interface.playAudio(resource).gain = gain
    }

    /// Crossfades birdsong into crickets as night falls.
    func setAmbience(night: Float, force: Bool = false) {
        guard force || abs(night - lastNight) > 0.02 else { return }
        lastNight = night
        updateLoops()
    }

    /// Fades the boss theme in or out; call a few times a second.
    func setBattleMusic(_ active: Bool, deltaTime: Double) {
        let target: Float = active ? 1 : 0
        let step = Float(deltaTime / (active ? 1.5 : 3)) // fade in fast, out slowly
        musicLevel = musicLevel < target ? min(target, musicLevel + step) : max(target, musicLevel - step)
        updateLoops()
    }

    /// Ambience crossfaded by time of day and hushed while the boss theme plays; silent when muted.
    private func updateLoops() {
        let night = max(lastNight, 0)
        let silent: Double = -80
        musicController?.gain = isMuted || musicLevel <= 0.001 ? silent : decibels(musicLevel) - 6
        dayController?.gain = isMuted ? silent : decibels((1 - night) * (1 - musicLevel * 0.7)) - 10
        nightController?.gain = isMuted ? silent : decibels(night * (1 - musicLevel * 0.7)) - 8
    }

    private func decibels(_ level: Float) -> Double {
        20 * log10(Double(max(level, 0.001)))
    }
}
