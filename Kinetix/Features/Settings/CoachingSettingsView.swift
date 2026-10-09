import SwiftUI
import AVFoundation
import TrainingEngine

/// Audio coaching: when pace cues fire, how strict they are, which voice, how loud,
/// and which announcements play.
struct CoachingSettingsView: View {
    @Bindable var settings: CoachingSettingsModel
    let units: UnitSystem

    @State private var voice = VoiceCoach()

    private var voices: [AVSpeechSynthesisVoice] {
        let language = String(AVSpeechSynthesisVoice.currentLanguageCode().prefix(2))
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    /// Tolerance shown per km or per mile.
    static func toleranceText(_ secondsPerKm: Double, units: UnitSystem) -> String {
        let value = units == .metric ? secondsPerKm : secondsPerKm * Units.metersPerMile / 1000
        return "\(Int(value.rounded())) s\(Units.paceUnitLabel(units))"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Pace cues", isOn: $settings.paceCuesEnabled)
                if settings.paceCuesEnabled {
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        HStack {
                            Text("Cue after off pace for")
                            Spacer()
                            Text("\(Int(settings.paceCueDelaySeconds)) s").font(KXFont.bodyEmphasis.monospacedDigit())
                        }
                        Slider(value: $settings.paceCueDelaySeconds, in: 10...60, step: 5)
                            .accessibilityLabel("Cue delay")
                            .accessibilityValue("\(Int(settings.paceCueDelaySeconds)) seconds")
                    }
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        HStack {
                            Text("Tolerance")
                            Spacer()
                            Text("± " + Self.toleranceText(settings.paceToleranceSecondsPerKm, units: units))
                                .font(KXFont.bodyEmphasis.monospacedDigit())
                        }
                        Slider(value: $settings.paceToleranceSecondsPerKm, in: 0...30, step: 1)
                            .accessibilityLabel("Pace tolerance")
                            .accessibilityValue(Self.toleranceText(settings.paceToleranceSecondsPerKm, units: units))
                    }
                    Toggle("Cues in warm-up & cool-down", isOn: $settings.cuesDuringWarmUpCoolDown)
                }
            } header: {
                Text("Pace cues")
            } footer: {
                Text("If you're outside your target pace by more than the tolerance for this long, you'll hear \"Ease off\" or \"Pick it up\". It repeats only if you're still off pace after the same time again.")
            }

            Section("Announcements") {
                Toggle(units == .metric ? "Kilometre splits" : "Mile splits", isOn: $settings.splitAnnouncementsEnabled)
                Toggle("Segment changes (reps, recoveries)", isOn: $settings.segmentAnnouncementsEnabled)
            }

            Section {
                Picker("Voice", selection: Binding(get: { settings.voiceIdentifier ?? "" },
                                                   set: { settings.voiceIdentifier = $0.isEmpty ? nil : $0 })) {
                    Text("System default").tag("")
                    ForEach(voices, id: \.identifier) { voice in
                        Text(voiceName(voice)).tag(voice.identifier)
                    }
                }
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text("\(Int((settings.cueVolume * 100).rounded()))%").font(KXFont.bodyEmphasis.monospacedDigit())
                    }
                    Slider(value: $settings.cueVolume, in: 0.2...1, step: 0.05)
                        .accessibilityLabel("Cue volume")
                }
                Button {
                    preview()
                } label: {
                    Label("Play a sample cue", systemImage: "speaker.wave.2.fill")
                }
            } header: {
                Text("Voice")
            } footer: {
                Text("Your music is lowered while Kinetix speaks, then comes back. Download higher-quality voices in iPhone Settings › Accessibility › Spoken Content › Voices.")
            }
        }
        .navigationTitle("Audio coaching")
        .navigationBarTitleDisplayMode(.inline)
        .tint(KXColor.accent)
        .onChange(of: settings.paceCueDelaySeconds) { settings.touch() }
        .onChange(of: settings.paceToleranceSecondsPerKm) { settings.touch() }
        .onChange(of: settings.paceCuesEnabled) { settings.touch() }
        .onChange(of: settings.splitAnnouncementsEnabled) { settings.touch() }
        .onChange(of: settings.segmentAnnouncementsEnabled) { settings.touch() }
        .onChange(of: settings.cuesDuringWarmUpCoolDown) { settings.touch() }
        .onChange(of: settings.voiceIdentifier) { settings.touch() }
        .onChange(of: settings.cueVolume) { settings.touch() }
    }

    private func voiceName(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = " (premium)"
        case .enhanced: quality = " (enhanced)"
        default: quality = ""
        }
        let region = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
        return "\(voice.name) · \(region)\(quality)"
    }

    private func preview() {
        voice.voiceIdentifier = settings.voiceIdentifier
        voice.volume = Float(settings.cueVolume)
        voice.prepare()
        let target = PaceRange(fastest: Pace(secondsPerKm: 285), slowest: Pace(secondsPerKm: 295))
        voice.speak(Announcer.paceCue(.tooSlow, target: target, units: units))
    }
}
