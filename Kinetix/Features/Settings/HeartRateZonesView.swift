import SwiftUI
import SwiftData
import TrainingEngine

/// Heart-rate zones: automatic (from age, raised by recorded runs) or their own.
struct HeartRateZonesView: View {
    let profileModel: UserProfileModel

    @Environment(\.modelContext) private var context
    @Query private var runs: [RunLogModel]

    @State private var custom = false
    @State private var maxHeartRate: Double = 190
    @State private var starts: [Double] = HeartRateZones.startShares.map { $0 * 190 }
    @State private var loaded = false

    private var automatic: HeartRateZones {
        var profile = profileModel.profile
        profile.heartRateZones = nil
        return StrainService.zones(profile: profile, runs: runs)
    }

    private var startsAreValid: Bool {
        zip(starts, starts.dropFirst()).allSatisfy { $0 < $1 } && (starts.last ?? 0) < maxHeartRate
    }

    /// What's shown: their own values while editing, else automatic.
    private var shown: HeartRateZones {
        custom && startsAreValid
            ? HeartRateZones(maxHeartRate: maxHeartRate, maxSource: .custom, starts: starts, isCustom: true)
            : automatic
    }

    var body: some View {
        List {
            Section {
                Toggle("Use my own zones", isOn: $custom)
                    .accessibilityIdentifier("zones.custom")
            } footer: {
                Text(custom
                     ? "Set your max heart rate and where each zone starts, e.g. from a lab test or your watch."
                     : sourceText(automatic))
            }

            if custom {
                Section("Max heart rate") {
                    KXStepper(label: "Max heart rate", value: $maxHeartRate, step: 1, range: 120...230,
                              format: { String(format: "%.0f bpm", $0) })
                        .frame(maxWidth: .infinity)
                    Button("Set zones from this max (50/60/70/80/90%)") {
                        starts = HeartRateZones.startShares.map { ($0 * maxHeartRate).rounded() }
                    }
                }
                Section {
                    ForEach(0..<5, id: \.self) { index in
                        KXStepper(label: "Zone \(index + 1) · \(HeartRateZones.names[index]) starts at",
                                  value: Binding(get: { starts[index] }, set: { starts[index] = $0.rounded() }),
                                  step: 1, range: 60...229, format: { String(format: "%.0f bpm", $0) })
                            .frame(maxWidth: .infinity)
                    }
                } header: {
                    Text("Zones")
                } footer: {
                    if !startsAreValid {
                        Text("Each zone must start higher than the one before, and below your max. Until then the automatic zones are used.")
                            .foregroundStyle(KXColor.danger)
                    }
                }
            }

            Section {
                ForEach(1...5, id: \.self) { zone in
                    let range = shown.range(of: zone)
                    LabeledContent("Zone \(zone) · \(HeartRateZones.names[zone - 1])",
                                   value: "\(Int(range.lowerBound))–\(Int(range.upperBound)) bpm")
                }
            } header: {
                Text(custom ? "Your zones" : "Your zones (automatic)")
            } footer: {
                Text("Strain counts each minute by its zone: zone 1 counts 1, zone 5 counts 5. Without heart rate, minutes × effort is used instead.")
            }
        }
        .navigationTitle("Heart rate zones")
        .navigationBarTitleDisplayMode(.inline)
        .tint(KXColor.accent)
        .onAppear(perform: load)
        .onChange(of: custom) { save() }
        .onChange(of: maxHeartRate) { save() }
        .onChange(of: starts) { save() }
    }

    private func sourceText(_ zones: HeartRateZones) -> String {
        let max = Int(zones.maxHeartRate)
        switch zones.maxSource {
        case .age: return "Max heart rate \(max) bpm, estimated from your age (208 − 0.7 × age). If your runs show higher, Kinetix uses that."
        case .recorded: return "Max heart rate \(max) bpm, from your recorded runs (higher than your age estimate)."
        case .typical: return "Max heart rate \(max) bpm, a typical value. Add your age in your training profile, or record runs with a heart-rate monitor, for a better estimate."
        case .custom: return "Max heart rate \(max) bpm."
        }
    }

    private func load() {
        guard !loaded else { return }
        let settings = profileModel.profile.heartRateZones
        let zones = StrainService.zones(profile: profileModel.profile, runs: runs)
        custom = settings?.isCustom ?? false
        maxHeartRate = settings?.maxHeartRate ?? zones.maxHeartRate
        starts = zones.starts
        loaded = true
    }

    private func save() {
        guard loaded else { return }
        let settings: HeartRateZoneSettings? = custom && startsAreValid
            ? HeartRateZoneSettings(maxHeartRate: maxHeartRate, zoneStarts: starts)
            : (custom ? profileModel.profile.heartRateZones : nil)
        guard settings != profileModel.profile.heartRateZones else { return }
        var profile = profileModel.profile
        profile.heartRateZones = settings
        profileModel.profile = profile
        try? context.save()
        SyncService.shared.requestSync()
    }
}
