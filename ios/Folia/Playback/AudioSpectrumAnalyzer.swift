import Accelerate
import Foundation

// Folia/Playback/AudioSpectrumAnalyzer.swift — bounded preallocated FFT/RMS calculations on actual decoded samples.
struct AudioAnalysisSnapshot: Sendable {
    var available = false
    var power: Double = 0
    var bass: Double = 0
    var lowMid: Double = 0
    var mid: Double = 0
    var highMid: Double = 0
    var treble: Double = 0
    var bands: [Double] { [bass, lowMid, mid, highMid, treble] }
}

final class AudioSpectrumAnalyzer {
    var sampleRate: Double = 44_100
    private let size = 1024
    private let log2Size: vDSP_Length = 10
    private var samples = [Float](repeating: 0, count: 1024)
    private var real = [Float](repeating: 0, count: 1024)
    private var imaginary = [Float](repeating: 0, count: 1024)
    private var window = [Float](repeating: 0, count: 1024)
    private var position = 0
    private let setup: FFTSetup?
    private(set) var snapshot = AudioAnalysisSnapshot()

    init() {
        setup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))
        vDSP_hann_window(&window, 1024, Int32(vDSP_HANN_NORM))
    }
    deinit { if let setup { vDSP_destroy_fftsetup(setup) } }

    // The audio callback writes into owned storage; no arrays, tasks or UI state are allocated per sample.
    @discardableResult func append(_ sample: Float) -> Bool {
        samples[position] = sample.isFinite ? max(-1, min(1, sample)) : 0
        position += 1
        guard position == size else { return false }
        position = 0; calculate(); return true
    }
    private func calculate() {
        var sum: Float = 0
        vDSP_svesq(samples, 1, &sum, vDSP_Length(size))
        snapshot = AudioAnalysisSnapshot(available: true, power: min(1, Double(sqrt(sum / Float(size)))))
        guard let setup, sampleRate.isFinite, sampleRate > 0 else { return }
        for index in 0..<size { real[index] = samples[index] * window[index]; imaginary[index] = 0 }
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imaginaryBuffer.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2Size, FFTDirection(FFT_FORWARD))
            }
        }
        var bass = 0.0, lowMid = 0.0, mid = 0.0, highMid = 0.0, treble = 0.0
        for index in 1..<(size / 2) {
            let frequency = Double(index) * sampleRate / Double(size)
            let magnitude = (Double(real[index]) * Double(real[index]) + Double(imaginary[index]) * Double(imaginary[index])) * 16 / Double(size * size)
            switch frequency {
            case 20..<150: bass += magnitude
            case 150..<400: lowMid += magnitude
            case 400..<2000: mid += magnitude
            case 2000..<6000: highMid += magnitude
            case 6000...20_000: treble += magnitude
            default: break
            }
        }
        snapshot.bass = min(1, sqrt(bass)); snapshot.lowMid = min(1, sqrt(lowMid))
        snapshot.mid = min(1, sqrt(mid)); snapshot.highMid = min(1, sqrt(highMid)); snapshot.treble = min(1, sqrt(treble))
    }
}
