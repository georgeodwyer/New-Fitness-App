import SwiftUI
import TrainingEngine

/// Settings → Apple Watch → Watch screens: the pages swiped through during a run.
struct WatchScreensView: View {
    @State private var settings = WatchControlsStore.screens
    @State private var editing: WatchScreen?

    var body: some View {
        List {
            Section {
                Toggle(isOn: $settings.showRepPage) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current rep").font(KXFont.bodyEmphasis)
                        Text("Built in · structured runs only").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                }
                .tint(KXColor.accent)
            } footer: {
                Text("Interval and other structured runs open on this page: pace against target, what's left of the rep and what's next.")
            }

            Section {
                ForEach($settings.screens) { $screen in
                    HStack(spacing: KXSpacing.md) {
                        WatchLayoutThumbnail(layout: screen.layout)
                        Button { editing = screen } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(screen.name).font(KXFont.custom(.condensedBold, 18, relativeTo: .headline)).textCase(.uppercase)
                                    .foregroundStyle(KXColor.ink)
                                Text("\(screen.layout.name) · \(screen.slots.map(\.pickerName).joined(separator: ", "))")
                                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Toggle(screen.name, isOn: $screen.isOn).labelsHidden().tint(KXColor.accent)
                    }
                    .accessibilityIdentifier("watchScreens.row")
                }
                .onMove { settings.screens.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { settings.screens.remove(atOffsets: $0) }

                Button {
                    let screen = WatchScreen(name: "My screen", layout: .oneTwo, metrics: [.pace, .distance, .time])
                    settings.screens.append(screen)
                    editing = screen
                } label: {
                    Label("New screen", systemImage: "plus.circle.fill").font(KXFont.bodyEmphasis)
                }
                .accessibilityIdentifier("watchScreens.add")
            } header: {
                Text("Your screens")
            } footer: {
                Text("Swipe through these during a run, in this order, after the controls. Tap one to change it, drag to reorder. Changes go to your watch straight away.")
            }

            Section {
                Button("Reset to the standard screens", role: .destructive) { settings = .standard }
            }
        }
        .navigationTitle("Watch screens")
        .toolbar { EditButton() }
        .onChange(of: settings) { _, new in WatchControlsStore.screens = new }
        .sheet(item: $editing) { screen in
            NavigationStack {
                WatchScreenEditor(screen: screen) { updated in
                    if let index = settings.screens.firstIndex(where: { $0.id == updated.id }) {
                        settings.screens[index] = updated
                    }
                }
            }
        }
    }
}

/// Edit one screen: its name, layout and what each slot shows.
struct WatchScreenEditor: View {
    @State var screen: WatchScreen
    let onSave: (WatchScreen) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var slotBeingChosen: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                TextField("Name", text: $screen.name)
                    .font(KXFont.custom(.condensedBold, 26, relativeTo: .title2))
                    .textCase(.uppercase)
                    .padding(KXSpacing.md)
                    .kxCard()

                KXOverline("Layout")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: KXSpacing.sm) {
                        ForEach(WatchLayout.allCases) { layout in
                            Button { screen.setLayout(layout) } label: {
                                VStack(spacing: 6) {
                                    WatchLayoutThumbnail(layout: layout, size: 54)
                                        .padding(3)
                                        .overlay(RoundedRectangle(cornerRadius: 17)
                                            .stroke(screen.layout == layout ? KXColor.accent : .clear, lineWidth: 2))
                                    Text(layout.name).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(layout.name)
                        }
                    }
                }

                KXOverline("Tap a slot to change it")
                WatchScreenPreview(screen: screen, selected: slotBeingChosen) { slotBeingChosen = $0 }
                    .frame(maxWidth: .infinity)
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle("Edit screen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if screen.name.trimmingCharacters(in: .whitespaces).isEmpty { screen.name = "My screen" }
                    screen.metrics = screen.slots
                    onSave(screen)
                    dismiss()
                }
            }
        }
        .sheet(item: Binding(get: { slotBeingChosen.map(SlotChoice.init) }, set: { slotBeingChosen = $0?.index })) { choice in
            MetricPicker(slot: choice.index, current: screen.slots[choice.index]) { metric in
                var metrics = screen.slots
                metrics[choice.index] = metric
                screen.metrics = metrics
                slotBeingChosen = nil
            }
            .presentationDetents([.medium, .large])
        }
    }

    private struct SlotChoice: Identifiable {
        let index: Int
        var id: Int { index }
    }
}

/// Pick what a slot shows, grouped as on the mockup.
private struct MetricPicker: View {
    let slot: Int
    let current: WatchMetric
    let onPick: (WatchMetric) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                Text("Slot \(slot + 1)").font(KXFont.title).textCase(.uppercase)
                ForEach(WatchMetric.Group.allCases, id: \.self) { group in
                    VStack(alignment: .leading, spacing: KXSpacing.sm) {
                        KXOverline(group.rawValue)
                        FlowChips(items: WatchMetric.allCases.filter { $0.group == group }, selected: current, onPick: onPick)
                    }
                }
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.surface.ignoresSafeArea())
    }
}

/// Wrapping row of metric chips.
private struct FlowChips: View {
    let items: [WatchMetric]
    let selected: WatchMetric
    let onPick: (WatchMetric) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items) { metric in
                Button { onPick(metric) } label: {
                    Text(metric.pickerName)
                        .font(KXFont.custom(.semiBold, 13, relativeTo: .footnote))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(metric == selected ? KXColor.accent : KXColor.surfaceTint, in: Capsule())
                        .foregroundStyle(metric == selected ? KXColor.onAccent : KXColor.ink)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A small picture of a layout: the big slot in the accent colour.
struct WatchLayoutThumbnail: View {
    let layout: WatchLayout
    var size: CGFloat = 44

    private func block(_ highlight: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(highlight ? KXColor.accent : Color.gray.opacity(0.45))
    }

    var body: some View {
        VStack(spacing: 2) {
            switch layout {
            case .one:
                block(true)
            case .oneTwo:
                block(true).frame(maxHeight: .infinity).layoutPriority(1)
                HStack(spacing: 2) { block(false); block(false) }
            case .oneFour:
                block(true)
                HStack(spacing: 2) { block(false); block(false) }
                HStack(spacing: 2) { block(false); block(false) }
            case .threeRows:
                block(false); block(false); block(false)
            case .sixSmall:
                ForEach(0..<3, id: \.self) { _ in HStack(spacing: 2) { block(false); block(false) } }
            }
        }
        .padding(size * 0.12)
        .frame(width: size, height: size * 1.2)
        .background(Color.black, in: RoundedRectangle(cornerRadius: size * 0.28))
        .overlay(RoundedRectangle(cornerRadius: size * 0.28).stroke(KXColor.border, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// The screen as it will look on the watch, with example numbers; slots are tappable.
struct WatchScreenPreview: View {
    let screen: WatchScreen
    var selected: Int?
    var onTap: (Int) -> Void = { _ in }

    var body: some View {
        let slots = screen.slots
        VStack(spacing: 7) {
            switch screen.layout {
            case .one:
                slot(0, slots[0], size: 64).frame(maxHeight: .infinity)
            case .oneTwo:
                slot(0, slots[0], size: 46).frame(maxHeight: .infinity)
                HStack(spacing: 7) { slot(1, slots[1]); slot(2, slots[2]) }
            case .oneFour:
                slot(0, slots[0], size: 40)
                HStack(spacing: 7) { slot(1, slots[1]); slot(2, slots[2]) }
                HStack(spacing: 7) { slot(3, slots[3]); slot(4, slots[4]) }
            case .threeRows:
                ForEach(0..<3, id: \.self) { slot($0, slots[$0], size: 28) }
            case .sixSmall:
                ForEach(0..<3, id: \.self) { row in HStack(spacing: 7) { slot(row * 2, slots[row * 2]); slot(row * 2 + 1, slots[row * 2 + 1]) } }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 26)
        .frame(width: 250, height: 300)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 60))
        .overlay(RoundedRectangle(cornerRadius: 60).stroke(KXColor.border, lineWidth: 2))
        .environment(\.colorScheme, .dark)
    }

    private func slot(_ index: Int, _ metric: WatchMetric, size: CGFloat = 22) -> some View {
        let isSelected = selected == index
        return Button { onTap(index) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(metric.label.uppercased())
                    .font(KXFont.custom(.condensedSemiBold, 10, relativeTo: .caption2))
                    .tracking(1)
                    .foregroundStyle(isSelected ? KXColor.accent : Color.gray)
                Text(Self.example(metric))
                    .font(KXFont.number(Self.isText(metric) ? min(size, 18) : size))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isSelected ? KXColor.accent.opacity(0.15) : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? KXColor.accent : Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: isSelected ? [] : [4, 3])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Slot \(index + 1): \(metric.pickerName)")
    }

    private static func isText(_ metric: WatchMetric) -> Bool { metric == .nextStep || metric == .paceVsTarget }

    /// Example numbers for the preview.
    static func example(_ metric: WatchMetric) -> String {
        switch metric {
        case .pace: return "5:12"
        case .averagePace: return "5:11"
        case .lapPace: return "5:08"
        case .targetPace: return "4:55–5:15"
        case .paceVsTarget: return "On target"
        case .heartRate: return "146"
        case .heartRateZone: return "Z3"
        case .averageHeartRate: return "141"
        case .timeInZone: return "12:40"
        case .stepRemaining: return "420 m"
        case .nextStep: return "90 s jog"
        case .repProgress: return "3/6"
        case .lapTime: return "3:11"
        case .lapDistance: return "0.62"
        case .distance: return "6.42"
        case .time: return "33:18"
        case .cadence: return "172"
        case .elevationGain: return "48"
        case .calories: return "412"
        case .exertion: return "34"
        case .timeOfDay: return "7:42"
        }
    }
}
