import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import TrainingEngine

/// The Record tab: start a run or a gym session without a plan, from scratch or
/// from a saved workout. Recorded sessions count towards training load like planned ones.
struct RecordView: View {
    @Query(filter: #Predicate<RunTemplateModel> { $0.deletedAt == nil }, sort: \RunTemplateModel.createdAt, order: .reverse)
    private var templates: [RunTemplateModel]
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<RouteModel> { $0.deletedAt == nil }, sort: \RouteModel.createdAt, order: .reverse)
    private var routes: [RouteModel]
    @State private var showImporter = false
    @State private var importMessage: String?

    private var units: UnitSystem { profiles.first?.units ?? UnitPreference.stored }

    /// Most recently used first.
    private var sortedTemplates: [RunTemplateModel] {
        templates.sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    KXScreenHeader(title: "Record")

                    HStack(spacing: KXSpacing.md) {
                        NavigationLink {
                            RunSetupView(initial: nil)
                        } label: {
                            choiceCard(title: "Run", detail: "Free run or a workout with pace targets",
                                       symbol: "figure.run", tint: KXColor.run)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("record.run")

                        NavigationLink {
                            GymSetupView()
                        } label: {
                            choiceCard(title: "Gym", detail: "Your own workouts, sets and weights",
                                       symbol: "dumbbell.fill", tint: KXColor.lift)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("record.gym")
                    }

                    VStack(alignment: .leading, spacing: KXSpacing.md) {
                        HStack {
                            KXOverline("My run workouts")
                            Spacer()
                            if !templates.isEmpty { Text("tap to start or edit").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary) }
                        }
                        if sortedTemplates.isEmpty {
                            KXEmptyState(symbol: "bookmark", title: "No saved workouts yet",
                                         message: "Build a run (say 2 × 10 min at threshold) and tap \u{201C}Save as template\u{201D} to reuse it.")
                        }
                        ForEach(sortedTemplates) { template in
                            NavigationLink {
                                RunSetupView(initial: template)
                            } label: {
                                templateRow(template)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    template.softDelete()
                                    try? context.save()
                                    SyncService.shared.requestSync()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .kxCard()

                    routesSection
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.gpx, .xml, .data]) { result in
                importGPX(result)
            }
        }
    }

    // MARK: Routes

    private var sortedRoutes: [RouteModel] {
        routes.sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    private var routesSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack {
                KXOverline("My routes")
                Spacer()
                if !routes.isEmpty { Text("tap to view, edit or run").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary) }
            }
            if routes.isEmpty {
                KXEmptyState(symbol: "map", title: "No routes yet",
                             message: "Plan one on the map (it follows roads and paths), make a loop of any distance, or import a GPX file.")
            }
            ForEach(sortedRoutes) { route in
                NavigationLink {
                    RoutePlannerView(existing: route)
                } label: {
                    routeRow(route)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    ShareLink(item: GPXFile(route: route.route), preview: SharePreview(route.name)) {
                        Label("Export GPX", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        route.softDelete()
                        try? context.save()
                        SyncService.shared.requestSync()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            if let importMessage {
                Label(importMessage, systemImage: "info.circle").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            HStack(spacing: KXSpacing.sm) {
                NavigationLink {
                    RoutePlannerView(existing: nil)
                } label: {
                    Label("Plan a route", systemImage: "map")
                }
                .buttonStyle(.kx(.secondary, fullWidth: true))
                .accessibilityIdentifier("record.planRoute")
                Button {
                    showImporter = true
                } label: {
                    Label("Import GPX", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.kx(.outlined, fullWidth: true))
                .accessibilityIdentifier("record.importGPX")
            }
        }
        .kxCard()
    }

    private func routeRow(_ route: RouteModel) -> some View {
        HStack(spacing: KXSpacing.md) {
            RouteShapeThumbnail(path: route.route.path)
                .frame(width: 64, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Text(DisplayFormat(units: units).distance(route.distanceMeters)
                     + (route.route.isLoop ? " loop" : "")
                     + (route.followsRoads ? "" : " · straight lines / imported"))
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(KXColor.inkTertiary).accessibilityHidden(true)
        }
        .padding(.vertical, KXSpacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func importGPX(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            importMessage = "Couldn't read that file."
            return
        }
        let parsed = GPXRoute.parse(text)
        guard parsed.points.count > 1 else {
            importMessage = "That file has no route in it. Pick a .gpx file with a track or route."
            return
        }
        let name = parsed.name ?? url.deletingPathExtension().lastPathComponent
        let model = RouteModel(route: RouteService.imported(name: name, points: parsed.points))
        context.insert(model)
        try? context.save()
        SyncService.shared.requestSync()
        importMessage = "Imported \u{201C}\(name)\u{201D}."
    }

    private func choiceCard(title: String, detail: String, symbol: String, tint: Color, badge: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 50, height: 50)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer()
                if let badge { KXChip(text: badge, variant: .outlined) }
            }
            Spacer(minLength: KXSpacing.sm)
            Text(title)
                .font(KXFont.custom(.condensedBold, 30, relativeTo: .title))
                .textCase(.uppercase)
                .foregroundStyle(KXColor.ink)
            Text(detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .padding(KXSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.18), KXColor.surface], startPoint: .topLeading, endPoint: .center))
                .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        }
        .shadow(color: KXShadow.color, radius: KXShadow.radius, y: KXShadow.y)
        .accessibilityElement(children: .combine)
    }

    private func templateRow(_ template: RunTemplateModel) -> some View {
        let workout = template.workout
        return VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(workout.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(KXColor.inkTertiary).accessibilityHidden(true)
            }
            if let structure = workout.structure, structure.segments.count > 1 {
                SessionStructureBar(structure: structure).frame(height: 8)
            }
            Text(workout.summary(units: units)).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary).lineLimit(2)
        }
        .padding(.vertical, KXSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A route's outline, scaled to fit: a small picture of the shape.
struct RouteShapeThumbnail: View {
    let path: [RouteCoordinate]

    var body: some View {
        GeometryReader { geo in
            let lats = path.map(\.latitude), lons = path.map(\.longitude)
            let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 1
            let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 1
            let span = max(maxLat - minLat, (maxLon - minLon) * 0.65, 0.00001)
            let inset: CGFloat = 8
            let size = min(geo.size.width, geo.size.height) - inset * 2
            Path { line in
                for (index, point) in path.enumerated() {
                    let x = inset + (geo.size.width - size) / 2 - inset + CGFloat((point.longitude - minLon) * 0.65 / span) * size
                    let y = inset + (geo.size.height - size) / 2 - inset + CGFloat((maxLat - point.latitude) / span) * size
                    let p = CGPoint(x: x, y: y)
                    if index == 0 { line.move(to: p) } else { line.addLine(to: p) }
                }
            }
            .stroke(KXColor.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}
