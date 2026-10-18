import AVFoundation
import MediaToolbox
import QuartzCore

// Folia/Playback/NativeAudioAnalysis.swift — non-mutating post-effects tap; unavailable streams never receive fabricated levels.
final class NativeAudioAnalysis {
    private let state = AudioTapState()

    func attach(to item: AVPlayerItem) async -> Bool {
        if let asset = item.asset as? AVURLAsset, asset.url.pathExtension.lowercased() == "m3u8" { return false }
        do {
            let protected = try await item.asset.load(.hasProtectedContent)
            guard !protected else { return false }
            let audioTracks = try await item.asset.loadTracks(withMediaType: .audio)
            guard let track = audioTracks.first else { return false }
            try Task.checkCancellation()
            let retained = Unmanaged.passRetained(state).toOpaque()
            var callbacks = MTAudioProcessingTapCallbacks(version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: retained,
                init: { _, info, storage in storage.pointee = info },
                finalize: { tap in Unmanaged<AudioTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
                prepare: { tap, _, format in
                    let state = Unmanaged<AudioTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    let format = format.pointee
                    state.supported = format.mFormatID == kAudioFormatLinearPCM && (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0 && format.mBitsPerChannel == 32
                    state.analyzer.sampleRate = format.mSampleRate
                }, unprepare: nil,
                process: { tap, frames, _, buffers, framesOut, flagsOut in
                    let status = MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut)
                    guard status == noErr else { framesOut.pointee = 0; return }
                    let state = Unmanaged<AudioTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    state.consume(buffers, frames: Int(framesOut.pointee))
                })
            var tap: MTAudioProcessingTap?
            let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
            guard status == noErr, let tap else { Unmanaged<AudioTapState>.fromOpaque(retained).release(); return false }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            let mix = AVMutableAudioMix(); mix.inputParameters = [parameters]; item.audioMix = mix
            return true
        } catch { return false }
    }
    func snapshot() -> AudioAnalysisSnapshot { state.read() }
}

private final class AudioTapState {
    let analyzer = AudioSpectrumAnalyzer()
    var supported = false
    private let lock = NSLock()
    private var latest = AudioAnalysisSnapshot()
    private var updatedAt: CFTimeInterval = 0

    // Float PCM is inspected in place and passed through unchanged. A contended UI read drops a snapshot instead of blocking audio.
    func consume(_ pointer: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard supported, frames > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(pointer)
        for frame in 0..<frames {
            var sum: Float = 0, channelCount = 0
            for buffer in buffers {
                let channels = Int(buffer.mNumberChannels)
                guard channels > 0, let data = buffer.mData,
                      (frame + 1) * channels * MemoryLayout<Float>.size <= Int(buffer.mDataByteSize) else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                for channel in 0..<channels { sum += samples[frame * channels + channel] }
                channelCount += channels
            }
            guard channelCount > 0 else { continue }
            if analyzer.append(sum / Float(channelCount)), lock.try() {
                latest = analyzer.snapshot; updatedAt = CACurrentMediaTime(); lock.unlock()
            }
        }
    }
    func read() -> AudioAnalysisSnapshot {
        lock.lock(); defer { lock.unlock() }
        return CACurrentMediaTime() - updatedAt < 1.5 ? latest : AudioAnalysisSnapshot()
    }
}

