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
        utterance.voice = voiceIdentifier.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
            ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        utterance.volume = volume
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.2
        synthesizer.speak(utterance)
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
