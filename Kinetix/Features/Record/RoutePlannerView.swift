import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import UniformTypeIdentifiers
import TrainingEngine

/// Plan a route on the map: tap to add points (the line follows roads and paths, or goes
/// straight), or make a loop of a set distance. Save it, export it as GPX, or run it.
struct RoutePlannerView: View {
    let existing: RouteModel?

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]

    @State private var route: PlannedRoute
    @State private var followRoads: Bool
    @State private var position: MapCameraPosition
    /// Where the map is centred. Kept outside SwiftUI state on purpose: updating it must not
    /// redraw the screen, or the map and the screen can keep nudging each other.
    @State private var mapCenter = MapCenter()
    /// The route being run, frozen when "Run it" is tapped.
    @State private var runRoute: PlannedRoute?
    @State private var isRouting = false
    @State private var note: String?
    @State private var buildTask: Task<Void, Never>?
    @State private var locationManager = CLLocationManager()

    @State private var showLoop = false
    @State private var loopDistance = 5.0
    @State private var loopBearing = Double.random(in: 0..<360)
    @State private var lastLoopStart: RouteCoordinate?

    @State private var showSave = false
    @State private var saveName = ""
    @State private var saved: RouteModel?
    @State private var savedMessage: String?

    init(existing: RouteModel?) {
        self.existing = existing
        let route = existing?.route ?? PlannedRoute(name: "", waypoints: [], path: [])
        _route = State(initialValue: route)
        _followRoads = State(initialValue: existing?.followsRoads ?? true)
        _position = State(initialValue: existing == nil ? .userLocation(fallback: .automatic) : .automatic)
        _saved = State(initialValue: existing)
        _saveName = State(initialValue: existing?.name ?? "")
    }

    private var units: UnitSystem { profiles.first?.units ?? UnitPreference.stored }
    private var format: DisplayFormat { DisplayFormat(units: units) }
    private var waypoints: [RouteCoordinate] { route.waypoints }
    private var hasRoute: Bool { route.path.count > 1 }

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                UserAnnotation()
                if hasRoute {
                    MapPolyline(coordinates: route.path.map(\.clCoordinate))
                        .stroke(KXColor.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array(waypoints.enumerated()), id: \.offset) { index, point in
                    Annotation(index == 0 ? "Start" : "", coordinate: point.clCoordinate) {
                        Circle()
                            .fill(index == 0 ? KXColor.success : KXColor.accent)
                            .frame(width: index == 0 ? 16 : 12, height: index == 0 ? 16 : 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2.5))
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onTapGesture { location in
                if let coordinate = proxy.convert(location, from: .local) {
                    add(RouteCoordinate(coordinate))
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                mapCenter.value = RouteCoordinate(context.region.center)
            }
            .accessibilityLabel("Map. Tap to add a point to your route.")
            .accessibilityIdentifier("route.map")
        }
        .overlay(alignment: .top) {
            if waypoints.isEmpty {
                Text("Tap the map to add your start, then each point to run through.")
                    .font(KXFont.callout)
                    .foregroundStyle(KXColor.ink)
                    .padding(KXSpacing.md)
                    .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    .padding(KXSpacing.screenMargin)
            }
        }
        .safeAreaInset(edge: .bottom) { panel }
        .navigationTitle(existing == nil && saved == nil ? "Plan a route" : (saved?.name ?? "Route"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasRoute {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: GPXFile(route: namedRoute), preview: SharePreview(namedRoute.name)) {
                        Label("Export GPX", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("route.export")
                }
            }
        }
        .onAppear {
            if locationManager.authorizationStatus == .notDetermined { locationManager.requestWhenInUseAuthorization() }
        }
        .onDisappear { buildTask?.cancel() }
        .navigationDestination(item: $runRoute) { route in
            RunSetupView(initial: nil, route: route)
        }
        .sheet(isPresented: $showLoop) { loopSheet }
        .alert("Save route", isPresented: $showSave) {
            TextField("Name", text: $saveName)
            Button("Save") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved routes sync to your account and can be picked when you start a run.")
        }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    KXOverline(route.isLoop ? "Loop" : "Distance", color: KXColor.accent)
                    Text(hasRoute ? format.distance(route.distanceMeters, decimals: 2) : "–")
                        .font(KXFont.metricSmall).foregroundStyle(KXColor.ink)
                        .accessibilityIdentifier("route.distance")
                }
                Spacer()
                if isRouting {
                    ProgressView().accessibilityLabel("Finding a route")
                }
            }
            if let note {
                Label(note, systemImage: "info.circle").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            if let savedMessage {
                Label(savedMessage, systemImage: "checkmark.circle.fill").font(KXFont.caption).foregroundStyle(KXColor.ink)
                    .symbolRenderingMode(.multicolor)
            }

            HStack(spacing: KXSpacing.sm) {
                toolButton("Undo", symbol: "arrow.uturn.backward", id: "route.undo") { undo() }
                    .disabled(waypoints.isEmpty)
                toolButton("To start", symbol: "arrow.triangle.capsulepath", id: "route.toStart") { backToStart() }
                    .disabled(waypoints.count < 2 || route.isLoop)
                toolButton("Loop", symbol: "point.3.filled.connected.trianglepath.dotted", id: "route.loop") { showLoop = true }
                toolButton("Clear", symbol: "trash", id: "route.clear") { clear() }
                    .disabled(waypoints.isEmpty)
            }

            Toggle(isOn: Binding(get: { followRoads }, set: { followRoads = $0; rebuild() })) {
                Text("Follow roads and paths").font(KXFont.callout)
            }
            .tint(KXColor.accent)
            .accessibilityIdentifier("route.followRoads")

            if lastLoopStart != nil && hasRoute {
                Button {
                    loopBearing = (loopBearing + 72).truncatingRemainder(dividingBy: 360)
                    makeLoop()
                } label: {
                    Label("Try another loop", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.kx(.secondary, fullWidth: true))
                .disabled(isRouting)
            }

            HStack(spacing: KXSpacing.sm) {
                Button(saved == nil ? "Save" : "Save changes") {
                    if saveName.isEmpty { saveName = defaultName }
                    showSave = true
                }
                .buttonStyle(.kx(.outlined, fullWidth: true))
                .disabled(!hasRoute || isRouting)
                .accessibilityIdentifier("route.save")
                Button {
                    runRoute = namedRoute
                } label: {
                    Label("Run it", systemImage: "figure.run")
                }
                .buttonStyle(.kx(.primary, fullWidth: true))
                .disabled(!hasRoute || isRouting)
                .accessibilityIdentifier("route.run")
            }
        }
        .padding(KXSpacing.screenMargin)
        .background(KXColor.background)
    }

    private func toolButton(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.body.weight(.semibold))
                Text(title).font(KXFont.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(KXColor.ink)
            .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: Loop

    private var loopStart: RouteCoordinate? {
        waypoints.first ?? locationManager.location.map { RouteCoordinate($0.coordinate) } ?? mapCenter.value
    }

    private var loopSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $loopDistance, in: 1...50, step: 0.5) {
                        HStack {
                            Text("Distance")
                            Spacer()
                            KXEditableNumber(display: loopDistance.formatted(.number.precision(.fractionLength(0...1))),
                                             accessibilityLabel: "Loop distance") { typed in
                                loopDistance = min(max((typed * 2).rounded() / 2, 1), 50)
                            }
                            Text(Units.distanceUnitLabel(units)).font(KXFont.bodyEmphasis)
                        }
                    }
                    .accessibilityIdentifier("route.loopDistance")
                } footer: {
                    Text(waypoints.isEmpty
                         ? "Starts from where you are (or the middle of the map) and comes back to the same spot."
                         : "Starts and finishes at your first point. This replaces the points you've added.")
                }
                Section {
                    Button("Make loop") {
                        showLoop = false
                        makeLoop()
                    }
                    .disabled(loopStart == nil)
                    .accessibilityIdentifier("route.makeLoop")
                }
            }
            .navigationTitle("Make a loop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showLoop = false } }
            }
        }
        .presentationDetents([.medium])
    }

    private func makeLoop() {
        guard let start = lastLoopStart ?? loopStart else { return }
        lastLoopStart = start
        let meters = units == .metric ? loopDistance * 1000 : loopDistance * 1609.344
        let id = route.id, followRoads = followRoads, bearing = loopBearing
        buildTask?.cancel()
        isRouting = true
        note = nil
        buildTask = Task {
            let loop = await RouteService.loop(name: route.name, start: start, targetMeters: meters, bearingDegrees: bearing,
                                               followRoads: followRoads)
            guard !Task.isCancelled else { return }
            var result = loop
            result.id = id
            route = result
            isRouting = false
            if !LoopGenerator.isCloseEnough(achievedMeters: loop.distanceMeters, targetMeters: meters) {
                note = "This is as close as the roads here allow. Try another loop, or move a point."
            }
            withAnimation { position = .automatic }
        }
    }

    // MARK: Editing

    private func add(_ point: RouteCoordinate) {
        lastLoopStart = nil
        setWaypoints(waypoints + [point])
    }

    private func undo() {
        guard !waypoints.isEmpty else { return }
        // A generated loop is one shape: undo removes it all.
        let wasGeneratedLoop = lastLoopStart != nil
        lastLoopStart = nil
        setWaypoints(wasGeneratedLoop ? [] : Array(waypoints.dropLast()))
    }

    private func backToStart() {
        guard let first = waypoints.first else { return }
        setWaypoints(waypoints + [first])
    }

    private func clear() {
        lastLoopStart = nil
        note = nil
        setWaypoints([])
    }

    private func setWaypoints(_ points: [RouteCoordinate]) {
        route.waypoints = points
        // Show the straight line straight away; the road-following line replaces it.
        route.path = points
        route.instructions = []
        rebuild()
    }

    private func rebuild() {
        let points = waypoints, followRoads = followRoads, id = route.id, name = route.name
        buildTask?.cancel()
        guard points.count > 1 else {
            isRouting = false
            route.followsRoads = followRoads
            return
        }
        isRouting = true
        buildTask = Task {
            let result = await RouteService.build(name: name, waypoints: points, followRoads: followRoads, id: id)
            guard !Task.isCancelled else { return }
            route = result.route
            isRouting = false
            note = result.allRouted ? nil : "No path found for part of this route, so it uses a straight line there."
        }
    }

    // MARK: Saving

    private var defaultName: String {
        let distance = format.distance(route.distanceMeters)
        return route.isLoop ? "\(distance) loop" : "\(distance) route"
    }

    private var namedRoute: PlannedRoute {
        var copy = route
        if copy.name.isEmpty { copy.name = saved?.name ?? defaultName }
        return copy
    }

    private func save() {
        route.name = saveName.trimmingCharacters(in: .whitespaces).isEmpty ? defaultName : saveName.trimmingCharacters(in: .whitespaces)
        if let saved {
            saved.route = route
            saved.touch()
        } else {
            let model = RouteModel(route: route)
            context.insert(model)
            saved = model
        }
        try? context.save()
        SyncService.shared.requestSync()
        savedMessage = "Saved to My routes"
    }
}

/// Holds the map centre without triggering redraws.
final class MapCenter {
    var value: RouteCoordinate?
}

// MARK: - GPX files

extension UTType {
    static let gpx = UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml
}

/// A route shared as a .gpx file (made when shared, not before).
struct GPXFile: Transferable {
    let route: PlannedRoute

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .gpx) { file in
            SentTransferredFile(try RouteService.gpxFile(for: file.route))
        }
    }
}
