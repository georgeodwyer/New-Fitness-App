import Foundation
import AVFoundation

/// Speaks run announcements over the user's earphones. Music is ducked (lowered) while
/// speaking rather than stopped, then restored.
///
/// The speech is rendered (`AVSpeechSynthesizer.write`) and played through Kinetix's own audio
/// engine, so when it ends Kinetix can stop the engine and hand the audio straight back: the
/// system speech player holds on to the audio for several seconds after it finishes, which
/// kept music quiet long after a cue. If rendering gives nothing (some voices), it falls back
/// to speaking directly.
@MainActor
final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var playerFormat: AVAudioFormat?
    var voiceIdentifier: String?
    /// 0...1
    var volume: Float = 1
    var isMuted = false
    private var deactivateTask: Task<Void, Never>?
    /// The metronome is clicking: the audio stays on, mixed with music rather than lowering it
    /// (voice included), until it stops.
    var keepsAudioActive = false {
        didSet {
            guard keepsAudioActive != oldValue else { return }
            prepare()
            if !keepsAudioActive, !isBusy { releaseAudio() }
        }
    }

    // The announcement being played, and those waiting.
    private var queue: [String] = []
    private var isBusy = false
    private var currentText = ""
    private var utteranceID = 0
    private var pendingBuffers = 0
    private var renderingDone = false
    private var receivedAudio = false
    private var fallbackTask: Task<Void, Never>?
    /// Spoken directly by the system (rendering gave nothing).
    private var fallbackUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
        engine.attach(player)
    }

    /// Configures the audio session for spoken prompts that duck other audio.
    func prepare() {
        let session = AVAudioSession.sharedInstance()
        if keepsAudioActive {
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } else {
            try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        }
    }

    func speak(_ text: String) {
        guard !isMuted, !text.isEmpty else { return }
        queue.append(text)
        startNext()
    }

    private func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voiceIdentifier.flatMap { AVSpeechSynthesisVoice(identifier: $0) } ?? Self.bestVoice()
        utterance.volume = volume
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        return utterance
    }

    private func startNext() {
        guard !isBusy, !queue.isEmpty else { return }
        let text = queue.removeFirst()
        currentText = text
        isBusy = true
        deactivateTask?.cancel()
        try? AVAudioSession.sharedInstance().setActive(true)
        utteranceID += 1
        let id = utteranceID
        pendingBuffers = 0
        renderingDone = false
        receivedAudio = false
        let utterance = makeUtterance(text)
        synthesizer.write(utterance) { [weak self] buffer in
            nonisolated(unsafe) let buffer = buffer
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(buffer, id: id) }
            }
        }
        // Nothing rendered after a moment: speak it the ordinary way instead.
        fallbackTask?.cancel()
        fallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled, self.utteranceID == id, !self.receivedAudio else { return }
            self.speakDirectly(text, id: id)
        }
    }

    private func receive(_ buffer: AVAudioBuffer, id: Int) {
        guard id == utteranceID, isBusy, fallbackUtterance == nil else { return }
        guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
            // The end of the rendering.
            renderingDone = true
            if !receivedAudio {
                // Rendering gave nothing at all: speak it the ordinary way.
                fallbackTask?.cancel()
                speakDirectly(currentText, id: id)
                return
            }
            finishIfDone(id: id)
            return
        }
        if !receivedAudio {
            receivedAudio = true
            fallbackTask?.cancel()
        }
        if playerFormat != pcm.format {
            player.stop()
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: pcm.format)
            playerFormat = pcm.format
        }
        player.volume = volume
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        pendingBuffers += 1
        player.scheduleBuffer(pcm, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, id == self.utteranceID else { return }
                    self.pendingBuffers -= 1
                    self.finishIfDone(id: id)
                }
            }
        }
        if !player.isPlaying { player.play() }
    }

    private func finishIfDone(id: Int) {
        guard id == utteranceID, renderingDone, pendingBuffers <= 0 else { return }
        finishedUtterance()
    }

    private func speakDirectly(_ text: String, id: Int) {
        guard id == utteranceID, isBusy else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = makeUtterance(text)
        fallbackUtterance = utterance
        synthesizer.speak(utterance)
    }

    private func finishedUtterance() {
        fallbackUtterance = nil
        isBusy = false
        if !queue.isEmpty {
            // A short gap between announcements.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(0.2))
                self?.startNext()
            }
            return
        }
        // Short delay so back-to-back announcements don't make music bounce up and down.
        deactivateTask?.cancel()
        deactivateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard let self, !Task.isCancelled, !self.isBusy, self.queue.isEmpty else { return }
            self.releaseAudio()
        }
    }

    /// Voices in the phone's language that sound like a person (no novelty voices), best first:
    /// Premium, then Enhanced, then the basic ones; the phone's exact accent before others.
    static func naturalVoices() -> [AVSpeechSynthesisVoice] {
        let code = AVSpeechSynthesisVoice.currentLanguageCode()
        let language = String(code.prefix(2))
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) && !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { a, b in
                let rankA = (a.quality.rawValue, a.language == code ? 1 : 0)
                let rankB = (b.quality.rawValue, b.language == code ? 1 : 0)
                return rankA != rankB ? rankA > rankB : a.name < b.name
            }
    }

    /// The most natural voice installed for the phone's language.
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        naturalVoices().first ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    /// True when only the basic (robotic-sounding) voices are installed.
    static var onlyBasicVoices: Bool {
        !naturalVoices().contains { $0.quality == .enhanced || $0.quality == .premium }
    }

    func stop() {
        queue.removeAll()
        utteranceID += 1
        fallbackTask?.cancel()
        fallbackUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        isBusy = false
        releaseAudio()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        nonisolated(unsafe) let utterance = utterance
        Task { @MainActor in self.directSpeechEnded(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        nonisolated(unsafe) let utterance = utterance
        Task { @MainActor in self.directSpeechEnded(utterance) }
    }

    /// Only for announcements spoken directly (the fallback); rendered ones end when played.
    private func directSpeechEnded(_ utterance: AVSpeechUtterance) {
        guard let fallbackUtterance, utterance === fallbackUtterance else { return }
        finishedUtterance()
    }

    /// Stops Kinetix's audio and lets the user's music return to full volume. Retries for a
    /// while if the system is still letting go of the audio.
    private func releaseAudio(attempt: Int = 1) {
        guard !isBusy else { return }
        player.stop()
        if engine.isRunning { engine.stop() }
        guard !keepsAudioActive, !synthesizer.isSpeaking else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            guard attempt < 20 else { return }
            deactivateTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(0.5))
                guard let self, !Task.isCancelled, !self.isBusy else { return }
                self.releaseAudio(attempt: attempt + 1)
            }
        }
    }
}
