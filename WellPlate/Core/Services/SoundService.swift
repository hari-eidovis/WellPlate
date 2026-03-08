import AudioToolbox
import AVFoundation

/// Lightweight service for playing short UI feedback sounds.
enum SoundService {

    private static var player: AVAudioPlayer?

    /// Soft confirmation "tink" — ideal for quick-log actions.
    static func playConfirmation() {
        AudioServicesPlaySystemSound(1057)
    }

    /// Plays a bundled sound file by name (without extension).
    /// Falls back silently if the resource isn't found.
    static func play(_ name: String, ext: String = "wav") {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.45
        player?.play()
    }
}
