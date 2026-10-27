import Foundation
import AVFoundation

/// Speaks run announcements over the user's earphones. Music is ducked (lowered)
/// while speaking rather than stopped, then restored.
@MainActor
final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    var voiceIdentifier: String?
    /// 0...1
    var volume: Float = 1
    var isMuted = false
    private var deactivateTask: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Configures the audio session for spoken prompts that duck other audio.
    func prepare() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
    }

    func speak(_ text: String) {
        guard !isMuted, !text.isEmpty else { return }
        deactivateTask?.cancel()
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voiceIdentifier.flatMap { AVSpeechSynthesisVoice(identifier: $0) } ?? Self.bestVoice()
        utterance.volume = volume
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.2
        synthesizer.speak(utterance)
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
        synthesizer.stopSpeaking(at: .immediate)
        releaseAudio()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedSpeaking() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedSpeaking() }
    }

    private func finishedSpeaking() {
        guard !synthesizer.isSpeaking else { return }
        // Short delay so back-to-back announcements don't make music bounce up and down.
        deactivateTask?.cancel()
        deactivateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            guard let self, !Task.isCancelled, !self.synthesizer.isSpeaking else { return }
            self.releaseAudio()
        }
    }

    private func releaseAudio() {
        // Lets the user's music return to full volume.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
