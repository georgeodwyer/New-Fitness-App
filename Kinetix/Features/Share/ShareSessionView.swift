import SwiftUI
import SwiftData
import PhotosUI
import TrainingEngine

/// Pick a card style, preview it, then share (any app), save to Photos, or send the sticker
/// straight to Instagram Stories.
struct ShareSessionView: View {
    enum Source {
        case run(RunLogModel)
        case strength(StrengthLogModel, records: Int)
    }

    let source: Source
    let units: UnitSystem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @State private var style: ShareCardStyle = .map
    @AppStorage("share.details.splits") private var showSplits = true
    @AppStorage("share.details.pace") private var showPace = true
    @AppStorage("share.details.heartRate") private var showHeartRate = true
    @AppStorage("share.details.efforts") private var showEfforts = true
    @State private var zones: HeartRateZones?
    @State private var previousBests: [BestEffortDistance: Double] = [:]
    @AppStorage("share.hideRouteEnds") private var hideEnds = true
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var mapImage: UIImage?
    @State private var rendered: UIImage?
    @State private var savedMessage: String?

    private var isRun: Bool { if case .run = source { return true } else { return false } }

    private var options: ShareDetailOptions {
        ShareDetailOptions(splits: showSplits, pace: showPace, heartRate: showHeartRate, effortsAndElevation: showEfforts)
    }

    private var styles: [ShareCardStyle] { isRun ? ShareCardStyle.allCases : [.map, .photo, .sticker] }

    private var data: ShareCardData {
        switch source {
        case .run(let log): return .run(log, units: units, hideEnds: hideEnds, zones: zones, previousBests: previousBests)
        case .strength(let log, let records): return .strength(log, units: units, records: records)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: KXSpacing.lg) {
                    Picker("Style", selection: $style) {
                        ForEach(styles) { Text($0 == .map && !isRun ? "Card" : $0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("share.style")

                    preview

                    if style == .photo {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(photo == nil ? "Choose a photo" : "Change photo", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.kx(.secondary, fullWidth: true))
                    }
                    if style == .details { detailToggles }
                    if isRun && style != .details {
                        Toggle(isOn: $hideEnds) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hide start and finish").font(KXFont.bodyEmphasis)
                                Text("Leaves the first and last 200 m off the map so it doesn't show where you live.")
                                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                            }
                        }
                        .kxCard()
                    }
                    if style == .sticker {
                        Text("A transparent sticker: share it to Instagram Stories and lay it over your own photo.")
                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    if let savedMessage {
                        Label(savedMessage, systemImage: "checkmark.circle.fill").font(KXFont.callout).symbolRenderingMode(.multicolor)
                    }
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .tint(KXColor.accent)
        .task(id: hideEnds) {
            if case .run(let log) = source {
                if zones == nil { loadRunContext(for: log) }
                mapImage = await ShareService.mapImage(for: hideEnds ? RunAnalysis.privacyTrimmed(log.route) : log.route)
            }
            renderCard()
        }
        .onChange(of: style) { renderCard() }
        .onChange(of: options) { renderCard() }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photo = image
                    renderCard()
                }
            }
        }
    }

    private var preview: some View {
        ZStack {
            if style == .sticker {
                // A dark backdrop so the sticker is visible.
                RoundedRectangle(cornerRadius: KXRadius.md).fill(CardColor.surfaceTint)
            }
            if let rendered {
                Image(uiImage: rendered).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: KXRadius.md))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: 300)
        .frame(minHeight: 300)
        .accessibilityLabel("Preview of the \(style.rawValue.lowercased()) card")
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: KXSpacing.sm) {
            if let rendered {
                ShareLink(item: ShareImage(image: rendered),
                          preview: SharePreview(data.title, image: Image(uiImage: rendered))) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.kx(.primary, fullWidth: true))
                .accessibilityIdentifier("share.share")
                HStack(spacing: KXSpacing.sm) {
                    Button {
                        UIImageWriteToSavedPhotosAlbum(rendered, nil, nil, nil)
                        savedMessage = "Saved to Photos"
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.kx(.outlined, fullWidth: true))
                    if ShareService.canShareToInstagramStories {
                        Button {
                            if let sticker = ShareService.render(data, style: .sticker, mapImage: nil, photo: nil) {
                                ShareService.shareToInstagramStories(sticker: sticker, background: style == .photo ? photo : nil)
                            }
                        } label: {
                            Label("Stories", systemImage: "camera.circle")
                        }
                        .buttonStyle(.kx(.outlined, fullWidth: true))
                    }
                }
            }
        }
        .padding(KXSpacing.screenMargin)
        .background(KXColor.background)
    }

    private func renderCard() {
        rendered = ShareService.render(data, style: style, mapImage: mapImage, photo: photo, options: options)
    }

    /// Ticks for what the Details card shows.
    private var detailToggles: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXOverline("Share run details")
            VStack(spacing: 0) {
                detailToggle("Splits", detail: "Pace for each \(units == .metric ? "km" : "mile"), as bars", isOn: $showSplits)
                Divider().overlay(KXColor.border)
                detailToggle("Time on pace", detail: "Each rep against its target", isOn: $showPace)
                Divider().overlay(KXColor.border)
                detailToggle("Heart rate", detail: "Average, max and time in zones", isOn: $showHeartRate)
                Divider().overlay(KXColor.border)
                detailToggle("Best efforts & elevation", detail: "Your fastest efforts and the climb", isOn: $showEfforts)
            }
            .kxCard(padding: 0)
        }
    }

    private func detailToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Text(detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, KXSpacing.sm)
    }

    /// Heart-rate zones and the best times from earlier runs (for "new best").
    private func loadRunContext(for log: RunLogModel) {
        let runs = ((try? context.fetch(FetchDescriptor<RunLogModel>())) ?? [])
            .filter { $0.isFinished && !$0.isSoftDeleted }
        zones = StrainService.zones(profile: profiles.first?.profile, runs: runs)
        var bests: [BestEffortDistance: Double] = [:]
        for run in runs where run.id != log.id && run.startedAt < log.startedAt && run.countsTowardsHistory
            && !run.isImportedFromStrava && run.distanceMeters >= 1000 {
            for (distance, seconds) in RunAnalysis.bestEfforts(route: run.route) where bests[distance].map({ seconds < $0 }) ?? true {
                bests[distance] = seconds
            }
        }
        previousBests = bests
    }
}
