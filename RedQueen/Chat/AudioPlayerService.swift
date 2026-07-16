import Foundation
import Observation
import AVFAudio
import MatrixRustSDK

/// Downloads and plays audio message attachments; one at a time.
@MainActor @Observable
final class AudioPlayerService: NSObject, AVAudioPlayerDelegate {
    private(set) var playingMessageID: String?
    private(set) var loadingMessageID: String?

    var client: Client?

    private var player: AVAudioPlayer?
    /// Keeps the SDK's temp file alive while it plays.
    private var fileHandle: MediaFileHandle?

    func toggle(messageID: String, attachment: AudioAttachment) {
        if playingMessageID == messageID {
            stop()
            return
        }
        guard let client, loadingMessageID == nil else { return }
        stop()
        loadingMessageID = messageID
        Task {
            defer { loadingMessageID = nil }
            do {
                let handle = try await client.getMediaFile(mediaSource: attachment.source,
                                                           filename: attachment.filename,
                                                           mimeType: attachment.mimetype ?? "audio/mp4",
                                                           useCache: true,
                                                           tempDir: nil)
                let path = try handle.path()

                #if os(iOS)
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .spokenAudio)
                try? session.setActive(true)
                #endif

                let player = try AVAudioPlayer(contentsOf: URL(filePath: path))
                player.delegate = self
                player.play()
                self.player = player
                fileHandle = handle
                playingMessageID = messageID
            } catch {
                // Playback failure is non-fatal; just reset state.
                playingMessageID = nil
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        fileHandle = nil
        playingMessageID = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
