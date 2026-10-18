import XCTest
@testable import Folia

// FoliaTests/NativeAudioAnalysisTests.swift — measured PCM RMS and frequency-band behavior, without playback or network.
final class NativeAudioAnalysisTests: XCTestCase {
    func testSilenceProducesZeroPower() {
        let analyzer = AudioSpectrumAnalyzer()
        for _ in 0..<1024 { analyzer.append(0) }
        XCTAssertEqual(analyzer.snapshot.power, 0, accuracy: 0.0001)
        XCTAssertTrue(analyzer.snapshot.available)
    }
    func testRealSineSamplesConcentrateInMidBand() {
        let analyzer = AudioSpectrumAnalyzer()
        analyzer.sampleRate = 48_000
        for index in 0..<1024 { analyzer.append(Float(sin(2 * Double.pi * 1000 * Double(index) / 48_000))) }
        let result = analyzer.snapshot
        XCTAssertEqual(result.power, 1 / sqrt(2), accuracy: 0.02)
        XCTAssertGreaterThan(result.mid, result.bass * 10)
        XCTAssertGreaterThan(result.mid, result.highMid * 10)
        XCTAssertGreaterThan(result.mid, 0.5)
    }
    func testInvalidSamplesCannotPoisonPublishedLevels() {
        let analyzer = AudioSpectrumAnalyzer()
        for _ in 0..<1024 { analyzer.append(.nan) }
        XCTAssertEqual(analyzer.snapshot.power, 0)
        XCTAssertTrue(analyzer.snapshot.bands.allSatisfy(\.isFinite))
    }
}
