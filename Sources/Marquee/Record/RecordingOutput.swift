import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Receives frames (and optional system audio) from an SCStream and encodes
/// them into an H.264 MP4 with AVAssetWriter. All writer access happens on
/// `queue`, which is also the stream's sample-handler queue.
final class RecordingOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let url: URL
    let queue = DispatchQueue(label: "Marquee.recording")

    /// Called (on `queue`) if the stream stops by itself, e.g. the display went away.
    var onStreamError: ((Error) -> Void)?

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let micInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var finished = false
    private var lastVideoSample: CMSampleBuffer?
    private var lastVideoTime: CMTime = .invalid

    /// True when both desktop audio and a microphone are recorded (two audio tracks).
    var hasTwoAudioTracks: Bool { audioInput != nil && micInput != nil }

    init(url: URL, width: Int, height: Int, fps: Int, captureAudio: Bool, captureMicrophone: Bool = false) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let bitsPerPixel = 0.08
        let bitrate = Int(Double(width * height * fps) * bitsPerPixel)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(2_000_000, min(bitrate, 40_000_000)),
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
            // Tag the video so players read its colors as recorded (sRGB frames, Rec. 709 tags).
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else { throw RecorderError.writerSetupFailed }
        writer.add(videoInput)

        audioInput = captureAudio ? RecordingOutput.addAudioInput(to: writer) : nil
        micInput = captureMicrophone ? RecordingOutput.addAudioInput(to: writer) : nil

        super.init()
        guard writer.startWriting() else {
            throw writer.error ?? RecorderError.writerSetupFailed
        }
    }

    private static func addAudioInput(to writer: AVAssetWriter) -> AVAssetWriterInput? {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 160_000,
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        return input
    }

    /// Appends a microphone buffer. Call on `queue`.
    func appendMicrophone(_ sampleBuffer: CMSampleBuffer) {
        guard !finished, sessionStarted, let micInput, micInput.isReadyForMoreMediaData, sampleBuffer.isValid else { return }
        micInput.append(sampleBuffer)
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !finished, sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            // ScreenCaptureKit also delivers "idle"/"blank" status frames with no new
            // pixels; only complete frames go into the file.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                  let rawStatus = attachments.first?[.status] as? Int,
                  let status = SCFrameStatus(rawValue: rawStatus),
                  status == .complete else { return }

            let time = sampleBuffer.presentationTimeStamp
            if !sessionStarted {
                writer.startSession(atSourceTime: time)
                sessionStarted = true
            }
            if videoInput.isReadyForMoreMediaData, videoInput.append(sampleBuffer) {
                lastVideoSample = sampleBuffer
                lastVideoTime = time
            }
        case .audio:
            guard sessionStarted, let audioInput, audioInput.isReadyForMoreMediaData else { return }
            audioInput.append(sampleBuffer)
        default:
            // .microphone (macOS 15) and future types aren't recorded.
            break
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { [weak self] in self?.onStreamError?(error) }
    }

    // MARK: - Finishing

    /// Finalizes the file. Returns nil if nothing was recorded.
    func finish() async -> URL? {
        let hasFrames: Bool = queue.sync {
            finished = true
            guard sessionStarted else { return false }
            holdLastFrameUntilNow()
            videoInput.markAsFinished()
            audioInput?.markAsFinished()
            micInput?.markAsFinished()
            writer.endSession(atSourceTime: lastVideoTime)
            lastVideoSample = nil
            return true
        }
        guard hasFrames else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        await writer.finishWriting()
        if writer.status != .completed {
            NSLog("Marquee: recording failed: \(String(describing: writer.error))")
            return nil
        }
        return url
    }

    /// When the screen is static at the end, no new frames arrive, which would cut the
    /// tail of the video short. Re-append the last frame stamped "now" to keep it.
    private func holdLastFrameUntilNow() {
        guard let last = lastVideoSample, lastVideoTime.isValid else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        let gap = CMTimeGetSeconds(CMTimeSubtract(now, lastVideoTime))
        // Sample times come from the host clock; sanity-check before trusting that.
        guard gap > 0.05, gap < 3600 else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: now, decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: last,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &copy
        )
        if status == noErr, let copy, videoInput.isReadyForMoreMediaData, videoInput.append(copy) {
            lastVideoTime = now
        }
    }
}

enum RecorderError: LocalizedError {
    case displayNotFound
    case writerSetupFailed
    case alreadyRecording

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "Could not find the display to record."
        case .writerSetupFailed: return "Could not set up the video encoder."
        case .alreadyRecording: return "A recording is already in progress."
        }
    }
}
