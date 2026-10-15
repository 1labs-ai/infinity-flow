import AVFoundation
import CoreAudio
import os

/// Seconds recorded since the meeting started, not counting pauses. Read from audio threads.
final class MeetingClock: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var startedAt = Date()
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0

    func start(at date: Date = .now) {
        lock.withLock {
            startedAt = date
            pausedAt = nil
            pausedTotal = 0
        }
    }

    func pause(at date: Date = .now) {
        lock.withLock { if pausedAt == nil { pausedAt = date } }
    }

    func resume(at date: Date = .now) {
        lock.withLock {
            if let pausedAt { pausedTotal += date.timeIntervalSince(pausedAt) }
            pausedAt = nil
        }
    }

    var isPaused: Bool { lock.withLock { pausedAt != nil } }

    func elapsed(at date: Date = .now) -> TimeInterval {
        lock.withLock {
            let end = pausedAt ?? date
            return max(0, end.timeIntervalSince(startedAt) - pausedTotal)
        }
    }
}

/// A finished chunk of one track, written as a 16 kHz mono WAV file.
struct MeetingChunk {
    let speaker: MeetingSpeaker
    let url: URL
    let start: Double
    let duration: Double
    /// False when the chunk held no speech; such chunks are deleted rather than transcribed.
    let hasSpeech: Bool
}

/// Writes one track (your mic, or the call's audio) into chunk files cut at natural pauses.
/// Buffers arrive on audio threads; all file work happens on a private serial queue.
final class TrackRecorder: @unchecked Sendable {
    let speaker: MeetingSpeaker
    private let folder: URL
    private let clock: MeetingClock
    private let queue: DispatchQueue
    private var policy = ChunkPolicy()
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var chunkStart: Double = 0
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var index = 0
    private var paused = false
    /// Levels are reported about 20 times a second rather than for every buffer.
    private var levelPeak: Float = 0
    private var levelSeconds: Double = 0

    /// Called on the recorder's queue when a chunk is finished.
    var onChunk: ((MeetingChunk) -> Void)?
    /// Called on the recorder's queue with a 0...1 level, about 20 times a second.
    var onLevel: ((Float) -> Void)?

    static let fileFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    init(speaker: MeetingSpeaker, folder: URL, clock: MeetingClock) {
        self.speaker = speaker
        self.folder = folder
        self.clock = clock
        queue = DispatchQueue(label: "InfinityFlow.meeting.\(speaker.rawValue)", qos: .userInitiated)
    }

    /// Takes a buffer from a capture callback. `channel` picks one channel; `nil` averages them all.
    func append(_ buffer: AVAudioPCMBuffer, channel: Int? = nil) {
        guard let samples = Self.mono(buffer, channel: channel) else { return }
        let rate = buffer.format.sampleRate
        let now = clock.elapsed()
        let level = AudioLevel.normalized(rms: samples.withUnsafeBufferPointer { AudioLevel.rms($0) })
        queue.async { [self] in
            reportLevel(level, seconds: Double(samples.count) / rate)
            write(samples, rate: rate, level: level, endingAt: now)
        }
    }

    /// Ends the current chunk and drops audio until `resume()`.
    func pause() {
        queue.async { [self] in
            paused = true
            finishChunk()
        }
    }

    func resume() {
        queue.async { [self] in paused = false }
    }

    /// Ends the last chunk. `completion` runs on the recorder's queue after its `onChunk`.
    func finish(completion: @escaping () -> Void) {
        queue.async { [self] in
            paused = true
            finishChunk()
            completion()
        }
    }

    private func reportLevel(_ level: Float, seconds: Double) {
        levelPeak = max(levelPeak, level)
        levelSeconds += seconds
        guard levelSeconds >= 0.05 else { return }
        onLevel?(paused ? 0 : levelPeak)
        levelPeak = 0
        levelSeconds = 0
    }

    private func write(_ samples: [Float], rate: Double, level: Float, endingAt elapsed: Double) {
        guard !paused, rate > 0 else { return }
        let seconds = Double(samples.count) / rate
        if file == nil { openChunk(start: max(0, elapsed - seconds)) }
        guard let file, let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false) else { return }
        if sourceFormat?.sampleRate != rate {
            sourceFormat = mono
            converter = AVAudioConverter(from: mono, to: Self.fileFormat)
        }
        guard let converter, let input = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }

        let capacity = AVAudioFrameCount(Double(samples.count) * Self.fileFormat.sampleRate / rate) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.fileFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        if error == nil, output.frameLength > 0 { try? file.write(from: output) }
        if policy.add(seconds: seconds, level: level) { finishChunk() }
    }

    private func openChunk(start: Double) {
        index += 1
        let url = folder.appendingPathComponent(String(format: "%@-%04d.wav", speaker.rawValue, index))
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        file = try? AVAudioFile(forWriting: url, settings: settings)
        fileURL = url
        chunkStart = start
        policy.reset()
    }

    private func finishChunk() {
        guard let fileURL, file != nil else { return }
        file = nil // closing the file finalizes the WAV header
        self.fileURL = nil
        let chunk = MeetingChunk(speaker: speaker, url: fileURL, start: chunkStart, duration: policy.length, hasSpeech: policy.hasSpeech)
        policy.reset()
        onChunk?(chunk)
    }

    /// One channel of a buffer, or the average of all channels, as Float samples.
    static func mono(_ buffer: AVAudioPCMBuffer, channel: Int?) -> [Float]? {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0 else { return nil }
        if let data = buffer.floatChannelData {
            if buffer.format.isInterleaved {
                let samples = UnsafeBufferPointer(start: data[0], count: frames * channels)
                if let channel { return stride(from: min(channel, channels - 1), to: samples.count, by: channels).map { samples[$0] } }
                return (0..<frames).map { frame in
                    var sum: Float = 0
                    for c in 0..<channels { sum += samples[frame * channels + c] }
                    return sum / Float(channels)
                }
            }
            if let channel { return Array(UnsafeBufferPointer(start: data[min(channel, channels - 1)], count: frames)) }
            var mixed = [Float](repeating: 0, count: frames)
            for c in 0..<channels {
                let samples = UnsafeBufferPointer(start: data[c], count: frames)
                for i in 0..<frames { mixed[i] += samples[i] }
            }
            return channels == 1 ? mixed : mixed.map { $0 / Float(channels) }
        }
        if let data = buffer.int16ChannelData, !buffer.format.isInterleaved {
            return Array(UnsafeBufferPointer(start: data[min(channel ?? 0, channels - 1)], count: frames)).map { Float($0) / 32_768 }
        }
        return nil
    }
}

/// Captures your microphone for a meeting. Echo cancellation keeps the other participants, playing
/// through your speakers, out of your track.
final class MeetingMicrophone {
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var echoCancellation = true
    private var startedAt = Date.distantPast
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Whether echo cancellation could be turned on for the current input.
    private(set) var cancelsEcho = false

    func start(echoCancellation: Bool) throws {
        self.echoCancellation = echoCancellation
        // Voice processing often can't start while another app (the call) holds the mic or the output device:
        // it fails with -10875. Notes without echo cancellation beat no notes, so fall back to the plain mic.
        if echoCancellation, let engine = try? makeEngine(voiceProcessing: true) {
            self.engine = engine
            cancelsEcho = true
        } else {
            engine = try makeEngine(voiceProcessing: false)
            cancelsEcho = false
        }
        startedAt = .now
        // A new default microphone or headset changes the input format; restart on the new device.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restart()
        }
    }

    private func makeEngine(voiceProcessing: Bool) throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if voiceProcessing {
            try input.setVoiceProcessingEnabled(true)
            input.voiceProcessingOtherAudioDuckingConfiguration =
                AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
            // Voice processing runs input and output as one unit, so the output side must be part of the graph.
            _ = engine.mainMixerNode
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw FlowError.noMicrophone }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.onBuffer?(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            if voiceProcessing { try? input.setVoiceProcessingEnabled(false) }
            throw error
        }
        return engine
    }

    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func restart() {
        // Turning on voice processing can itself report a configuration change; don't restart in a loop.
        guard Date.now.timeIntervalSince(startedAt) > 2 else { return }
        let handler = onBuffer
        stop()
        onBuffer = handler
        try? start(echoCancellation: echoCancellation)
    }
}

/// Captures everything your Mac plays (the other people on a call) with a Core Audio process tap.
/// Infinity Flow's own sounds are excluded. macOS asks once for "System Audio Recording" permission;
/// when it is denied the tap delivers silence.
final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private let queue = DispatchQueue(label: "InfinityFlow.meeting.systemAudio", qos: .userInitiated)
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    func start() throws {
        try startTap()
        // The tap is clocked by the output device; follow the user when they switch speakers or headphones.
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.stopTap()
            try? self.startTap()
        }
        var address = AudioObjects.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
        outputListener = listener
    }

    func stop() {
        if let outputListener {
            var address = AudioObjects.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, outputListener)
        }
        outputListener = nil
        stopTap()
    }

    private func startTap() throws {
        let excluded = AudioObjects.processObject(pid: getpid()).map { [$0] } ?? []
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.uuid = UUID()
        description.name = "Infinity Flow meeting notes"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try AudioObjects.check(AudioHardwareCreateProcessTap(description, &tap), "create the system audio tap")
        tapID = tap

        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = AudioObjects.address(kAudioTapPropertyFormat)
        try AudioObjects.check(AudioObjectGetPropertyData(tap, &formatAddress, 0, nil, &size, &streamDescription), "read the tap format")
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            stopTap()
            throw FlowError.api("System audio has an unsupported format.")
        }

        let outputUID = try AudioObjects.defaultOutputDeviceUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Infinity Flow meeting audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        do {
            try AudioObjects.check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device), "create the meeting audio device")
            aggregateID = device
            try AudioObjects.check(AudioDeviceCreateIOProcIDWithBlock(&procID, device, queue) { [weak self] _, input, _, _, _ in
                guard let self, let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil) else { return }
                self.onBuffer?(buffer)
            }, "listen to system audio")
            try AudioObjects.check(AudioDeviceStart(device, procID), "start system audio")
        } catch {
            stopTap()
            throw error
        }
    }

    private func stopTap() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }
}

/// Small helpers over the Core Audio C API.
enum AudioObjects {
    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func check(_ status: OSStatus, _ action: String) throws {
        guard status == noErr else { throw FlowError.api("Couldn't \(action) (error \(status)).") }
    }

    static func processObject(pid: pid_t) -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    static func defaultOutputDeviceUID() throws -> String {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device), "find your speakers")
        guard let uid = string(device, kAudioDevicePropertyDeviceUID) else { throw FlowError.api("Couldn't find your speakers.") }
        return uid
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Other apps that are recording from a microphone right now, by bundle ID.
    static func appsUsingMicrophone() -> [String] {
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        let ownPID = getpid()
        return objects.compactMap { object in
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddress = self.address(kAudioProcessPropertyPID)
            guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &pid) == noErr, pid != ownPID else { return nil }
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = self.address(kAudioProcessPropertyIsRunningInput)
            guard AudioObjectGetPropertyData(object, &runningAddress, 0, nil, &runningSize, &running) == noErr, running != 0 else { return nil }
            return string(object, kAudioProcessPropertyBundleID)
        }
    }
}
