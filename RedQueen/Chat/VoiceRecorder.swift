import Foundation
import Observation
import AVFAudio
import CocoaLumberjackSwift

/// Records mono AAC voice notes with live level metering for the waveform.
@MainActor @Observable
final class VoiceRecorder {
    struct Recording: Hashable {
        let fileURL: URL
        let duration: TimeInterval
        /// Normalized 0...1 amplitude samples, downsampled for MSC3246.
        let waveform: [Float]
    }

    private(set) var isRecording = false
    private(set) var duration: TimeInterval = 0
    /// Live level (0...1) for the recording indicator.
    private(set) var currentLevel: Float = 0

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var levels: [Float] = []

    /// Starts recording; returns false if mic permission is denied.
    func start() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else {
            DDLogWarn("🎙️ [VoiceRecorder] start: mic permission denied")
            return false
        }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default,
                                 options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
        #endif

        let url = FileManager.default.temporaryDirectory
            .appending(component: "voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000,
        ]
        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            DDLogError("💥 [VoiceRecorder] AVAudioRecorder init FAILED: \(error)")
            return false
        }
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            DDLogError("💥 [VoiceRecorder] recorder.record() returned false")
            return false
        }

        self.recorder = recorder
        levels = []
        duration = 0
        currentLevel = 0
        isRecording = true

        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleMeter() }
        }
        return true
    }

    /// Stops and returns the recording, or nil when discarding / too short.
    func stop(discard: Bool = false) -> Recording? {
        meterTimer?.invalidate()
        meterTimer = nil
        guard let recorder else { return nil }
        let url = recorder.url
        let recordedDuration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        isRecording = false
        currentLevel = 0

        guard !discard, recordedDuration >= 0.5 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return Recording(fileURL: url,
                         duration: recordedDuration,
                         waveform: Self.downsample(levels, to: 100))
    }

    private func sampleMeter() {
        guard let recorder, isRecording else { return }
        recorder.updateMeters()
        // dB (-160...0) → linear 0...1
        let level = pow(10, recorder.averagePower(forChannel: 0) / 20)
        levels.append(level)
        currentLevel = level
        duration = recorder.currentTime
    }

    private static func downsample(_ samples: [Float], to count: Int) -> [Float] {
        guard samples.count > count else { return samples }
        let bucketSize = Double(samples.count) / Double(count)
        return (0..<count).map { bucket in
            let start = Int(Double(bucket) * bucketSize)
            let end = min(Int(Double(bucket + 1) * bucketSize), samples.count)
            let slice = samples[start..<max(end, start + 1)]
            return slice.max() ?? 0
        }
    }
}
