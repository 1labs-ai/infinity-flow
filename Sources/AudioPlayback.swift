import AVFoundation
import Observation

/// Plays one saved recording at a time from History.
@MainActor
@Observable
final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayback()

    private(set) var playingID: UUID?
    @ObservationIgnored private var player: AVAudioPlayer?

    func toggle(_ transcript: Transcript) {
        if playingID == transcript.uuid {
            stop()
            return
        }
        stop()
        guard let url = transcript.audioURL, let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        player.play()
        self.player = player
        playingID = transcript.uuid
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
