import AVFoundation
import CoreMedia

/// Captures a microphone with AVCaptureSession. It runs before recording too, so the
/// toolbar can show a live level meter; while recording, buffers go to `sink`.
///
/// Samples are delivered as 48 kHz stereo float PCM (the same format ScreenCaptureKit
/// uses for desktop audio) and re-timed onto the host clock, so they line up with the
/// screen frames in the file.
final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
    }

    enum CaptureError: LocalizedError {
        case noDevice
        case cannotUse(String)

        var errorDescription: String? {
            switch self {
            case .noDevice: return "No microphone is connected."
            case .cannotUse(let name): return "Marquee couldn't use \(name)."
            }
        }
    }

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "Marquee.microphone")
    private let lock = NSLock()
    private var _sink: ((CMSampleBuffer) -> Void)?
    private(set) var deviceName: String?

    private var _muted = false

    /// While muted, silence is recorded in place of the microphone, so the voice track keeps
    /// its timing and the video stays in sync.
    var muted: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _muted }
        set { lock.lock(); _muted = newValue; lock.unlock() }
    }

    /// Receives re-timed sample buffers while recording. Called on a private queue.
    var sink: ((CMSampleBuffer) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _sink }
        set { lock.lock(); _sink = newValue; lock.unlock() }
    }

    // MARK: - Devices and permission

    static func devices() -> [Device] {
        let types: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            types = [.microphone, .external]
        } else {
            types = [.builtInMicrophone, .externalUnknown]
        }
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .audio, position: .unspecified)
            .devices
            .map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    static var defaultDeviceID: String? {
        AVCaptureDevice.default(for: .audio)?.uniqueID
    }

    static var authorization: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    // MARK: - Running

    /// Starts (or switches) the microphone. Safe to call again with another device.
    func start(deviceID: String?) throws {
        let device = deviceID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .audio)
        guard let device else { throw CaptureError.noDevice }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CaptureError.cannotUse(device.localizedName)
        }

        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CaptureError.cannotUse(device.localizedName)
        }
        session.addInput(input)
        if session.outputs.isEmpty {
            output.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
        session.commitConfiguration()
        deviceName = device.localizedName

        // startRunning blocks until the device is up, so keep it off the main thread.
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sink = nil
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Current input level from 0 (silence, -50 dB or quieter) to 1 (0 dB).
    var level: Float {
        guard let channels = output.connections.first?.audioChannels, !channels.isEmpty else { return 0 }
        let db = channels.map(\.averagePowerLevel).max() ?? -160
        return max(0, min(1, (db + 50) / 50))
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let sink else { return }
        let buffer = retimedToHostClock(sampleBuffer) ?? sampleBuffer
        sink(muted ? (Self.silenced(buffer) ?? buffer) : buffer)
    }

    /// A copy of an audio buffer with the same format and timing, but silent.
    private static func silenced(_ buffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let format = CMSampleBufferGetFormatDescription(buffer),
              let source = CMSampleBufferGetDataBuffer(buffer) else { return nil }
        let length = CMBlockBufferGetDataLength(source)
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                                                 offsetToData: 0, dataLength: length,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
              let block, CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: length) == noErr
        else { return nil }
        var silent: CMSampleBuffer?
        let status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: CMSampleBufferGetNumSamples(buffer),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(buffer),
            packetDescriptions: nil, sampleBufferOut: &silent)
        return status == noErr ? silent : nil
    }

    /// Capture timestamps use the session's clock (often the audio device's own clock);
    /// ScreenCaptureKit uses the host clock. Convert so both share one timeline.
    private func retimedToHostClock(_ buffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let clock = session.synchronizationClock else { return nil }
        let host = CMClockGetHostTimeClock()
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return nil }
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count)
        for i in timing.indices {
            timing[i].presentationTimeStamp = CMSyncConvertTime(timing[i].presentationTimeStamp, from: clock, to: host)
            timing[i].decodeTimeStamp = .invalid
        }
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: buffer,
            sampleTimingEntryCount: count, sampleTimingArray: &timing, sampleBufferOut: &copy
        )
        return status == noErr ? copy : nil
    }
}
