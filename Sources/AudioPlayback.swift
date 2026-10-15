import AVFoundation
import Observation

/// Plays one saved recording at a time, from History or a meeting transcript.
@MainActor
@Observable
final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayback()

    private(set) var playingID: UUID?
    @ObservationIgnored private var player: AVAudioPlayer?

    func toggle(_ transcript: Transcript) {
        toggle(id: transcript.uuid, url: transcript.audioURL)
    }

    func toggle(id: UUID, url: URL?) {
        if playingID == id {
            stop()
            return
        }
        stop()
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        player.play()
        self.player = player
        playingID = id
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
