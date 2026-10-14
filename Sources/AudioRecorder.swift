import AVFoundation

/// Captures the microphone into a 16 kHz mono WAV file and reports input levels.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private(set) var fileURL: URL?

    /// Called on the audio thread with a 0...1 level for each buffer.
    var onLevel: ((Float) -> Void)?

    func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw FlowError.noMicrophone }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("infinity-flow-\(UUID().uuidString).wav")
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: fileSettings)
        guard let converter = AVAudioConverter(from: inputFormat, to: file.processingFormat) else { throw FlowError.noMicrophone }
        self.file = file
        self.converter = converter
        self.fileURL = url

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops capture and returns the recorded file and its duration.
    func stop() -> (url: URL, duration: TimeInterval)? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        defer { file = nil; converter = nil }
        guard let file, let fileURL else { return nil }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        return (fileURL, duration)
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        if let channel = buffer.floatChannelData?[0] {
            let level = AudioLevel.normalized(rms: AudioLevel.rms(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
            onLevel?(level)
        }
        guard let file, let converter else { return }
        let ratio = file.processingFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 {
            try? file.write(from: out)
        }
    }
}
