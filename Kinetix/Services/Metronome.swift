import Foundation
import AVFoundation

/// A soft click at the runner's chosen steps per minute, mixed over their music (not ducking
/// it). Set by hand on the run screen; remembered for next time.
@MainActor
final class Metronome {
    enum Keys {
        static let enabled = "metronome.enabled"
        static let stepsPerMinute = "metronome.spm"
    }

    static let range = 140...200
    static var storedEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.enabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.enabled) }
    }
    static var storedStepsPerMinute: Int {
        get { (UserDefaults.standard.object(forKey: Keys.stepsPerMinute) as? Int).map { min(max($0, range.lowerBound), range.upperBound) } ?? 170 }
        set { UserDefaults.standard.set(min(max(newValue, range.lowerBound), range.upperBound), forKey: Keys.stepsPerMinute) }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var attached = false
    private(set) var isPlaying = false
    var volume: Float = 0.7

    /// Starts (or restarts at a new rate) the click.
    func start(stepsPerMinute: Int) {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
        if !attached {
            engine.attach(player)
            attached = true
        }
        let format = engine.outputNode.inputFormat(forBus: 0)
        let rate = format.sampleRate > 0 ? format.sampleRate : 44_100
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = Self.clickBuffer(format: mono, stepsPerMinute: stepsPerMinute, volume: volume) else { return }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: mono)
        player.stop()
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            return
        }
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        isPlaying = true
    }

    func stop() {
        guard isPlaying else { return }
        player.stop()
        engine.pause()
        isPlaying = false
    }

    /// One beat: a short, soft woodblock-like click, then silence until the next step.
    static func clickBuffer(format: AVAudioFormat, stepsPerMinute: Int, volume: Float) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * 60 / Double(max(stepsPerMinute, 1)))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        let clickFrames = Int(rate * 0.03)
        for frame in 0..<Int(frames) {
            guard frame < clickFrames else { samples[frame] = 0; continue }
            let t = Double(frame) / rate
            let envelope = exp(-t * 160)
            let tone = sin(2 * .pi * 1_600 * t) * 0.7 + sin(2 * .pi * 2_400 * t) * 0.3
            samples[frame] = Float(tone * envelope) * volume
        }
        return buffer
    }
}
