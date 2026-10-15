import SwiftUI
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
    @State private var style: ShareCardStyle = .map
    @AppStorage("share.hideRouteEnds") private var hideEnds = true
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var mapImage: UIImage?
    @State private var rendered: UIImage?
    @State private var savedMessage: String?

    private var isRun: Bool { if case .run = source { return true } else { return false } }

    private var data: ShareCardData {
        switch source {
        case .run(let log): return .run(log, units: units, hideEnds: hideEnds)
        case .strength(let log, let records): return .strength(log, units: units, records: records)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: KXSpacing.lg) {
                    Picker("Style", selection: $style) {
                        ForEach(ShareCardStyle.allCases) { Text($0 == .map && !isRun ? "Card" : $0.rawValue).tag($0) }
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
                    if isRun {
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
                mapImage = await ShareService.mapImage(for: hideEnds ? RunAnalysis.privacyTrimmed(log.route) : log.route)
            }
            renderCard()
        }
        .onChange(of: style) { renderCard() }
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
                // A checkerboard-free dark backdrop so the white sticker is visible.
                RoundedRectangle(cornerRadius: KXRadius.md).fill(Color(red: 0.12, green: 0.16, blue: 0.15))
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
        rendered = ShareService.render(data, style: style, mapImage: mapImage, photo: photo)
    }
}
