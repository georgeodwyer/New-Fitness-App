import SwiftUI
import MapKit
import TrainingEngine

/// The running trainer: get ready, then follow the structured run with live pace,
/// distance, time, heart rate and spoken coaching.
struct RunWorkoutView: View {
    @State private var model: RunWorkoutModel
    let onClose: () -> Void

    @State private var showFinishConfirm = false
    @State private var showEffort = false
    @State private var showLeave = false
    @State private var saved = false
    @State private var askHeartRate = false

    init(model: RunWorkoutModel, onClose: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onClose = onClose
    }

    private var format: DisplayFormat { DisplayFormat(units: model.units) }

    var body: some View {
        Group {
            if saved, let summary = model.finalSummary {
                RunSummaryView(title: model.title, summary: summary, units: model.units, simulated: model.isSimulated, log: model.log, onDone: onClose)
            } else if model.phase == .ready {
                ready
            } else {
                running
            }
        }
        .background(KXColor.background.ignoresSafeArea())
    }

    // MARK: Ready

    private var ready: some View {
        VStack(spacing: 0) {
            header(trailing: AnyView(EmptyView()))
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        Text(model.title).font(KXFont.display).foregroundStyle(KXColor.ink)
                        Text(model.planned?.summary ?? "").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    }
                    gpsStatusCard
                    if let route = model.plannedRoute {
                        VStack(alignment: .leading, spacing: KXSpacing.sm) {
                            KXSectionHeader("Your route", subtitle: "\(route.name) · \(format.distance(route.distanceMeters))")
                            RouteMap(route: [], planned: route.path)
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                            Label("You'll hear each turn before you reach it, and a warning if you leave the route.",
                                  systemImage: "arrow.triangle.turn.up.right.diamond")
                                .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        }
                        .kxCard()
                    }
                    if let structure = model.structure {
                        VStack(alignment: .leading, spacing: KXSpacing.sm) {
                            KXSectionHeader("Your session")
                            ForEach(Array(structure.segments.enumerated()), id: \.offset) { _, segment in
                                HStack {
                                    Circle().fill(segment.kind == .work ? KXColor.accent : KXColor.teal).frame(width: 8, height: 8)
                                        .accessibilityHidden(true)
                                    Text(segment.label ?? segment.kind.displayName).font(KXFont.callout)
                                    Text(format.segmentLength(segment.length)).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                                    Spacer()
                                    if let target = segment.targetPace {
                                        Text(format.paceRange(target)).font(KXFont.caption.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .kxCard()
                    }
                    Label("Audio coaching uses your earphones and lowers your music briefly while it speaks. Your screen can lock: tracking keeps going.",
                          systemImage: "headphones")
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                }
                .padding(KXSpacing.screenMargin)
            }
            Button(model.hasGPSFix ? "Start run" : "Start without GPS lock") {
                if model.shouldAskHeartRateSource { askHeartRate = true } else { model.start() }
            }
                .buttonStyle(.kx(.primary, fullWidth: true))
                .disabled(model.needsPermission)
                .padding(KXSpacing.screenMargin)
        }
        .onAppear { model.prepare() }
        .confirmationDialog("Heart rate from?", isPresented: $askHeartRate, titleVisibility: .visible) {
            // Last time's answer first.
            if IntegrationSettings.shared.runHeartRateSource == .strap {
                Button(model.strapName) { model.start(heartRateSource: .strap) }
                Button("Apple Watch") { model.start(heartRateSource: .watch) }
            } else {
                Button("Apple Watch") { model.start(heartRateSource: .watch) }
                Button(model.strapName) { model.start(heartRateSource: .strap) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your chest strap and Apple Watch can both read heart rate. A strap is usually more accurate.")
        }
    }

    private var gpsStatusCard: some View {
        HStack(spacing: KXSpacing.md) {
            Image(systemName: model.isSimulated ? "point.topleft.down.to.point.bottomright.curvepath" : "location.fill")
                .foregroundStyle(model.hasGPSFix ? KXColor.success : KXColor.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(gpsTitle).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Text(gpsDetail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            Spacer()
            if model.needsPermission {
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.kx(.secondary))
            }
        }
        .kxCard(model.hasGPSFix ? .tinted : .accent)
        .accessibilityElement(children: .combine)
    }

    private var gpsTitle: String {
        if model.isSimulated { return "Simulated GPS (\(Int(model.simulationSpeed ?? 1))× speed)" }
        if model.needsPermission { return "Location access is off" }
        return model.hasGPSFix ? "GPS ready" : "Finding GPS…"
    }

    private var gpsDetail: String {
        if model.isSimulated { return "A virtual runner loops Hyde Park, sometimes off pace so you can hear the coaching." }
        if model.needsPermission { return "Kinetix needs your location during runs to measure pace and distance. Turn it on in Settings." }
        return model.hasGPSFix ? "Accurate location found." : "Stand still outdoors for a moment for the best start."
    }

    // MARK: Running

    private var running: some View {
        VStack(spacing: 0) {
            header(trailing: AnyView(
                Text(Units.formatMinutesSeconds(model.snapshot.elapsedSeconds))
                    .font(KXFont.bodyEmphasis.monospacedDigit())
                    .foregroundStyle(KXColor.ink)
                    .accessibilityLabel("Elapsed \(Units.formatMinutesSeconds(model.snapshot.elapsedSeconds))")
            ))
            ScrollView {
                VStack(spacing: KXSpacing.md) {
                    if let status = model.routeStatus { routeCard(status) }
                    RouteMap(route: model.route, planned: model.plannedRoute?.path ?? [], followLatest: true)
                        .frame(height: model.plannedRoute == nil ? 170 : 220)
                        .clipShape(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if model.isSimulated {
                                KXChip(text: "Simulated GPS", variant: .inverted).padding(KXSpacing.sm)
                            }
                        }
                    segmentCard
                    telemetryCard
                    pacerCard
                }
                .padding(.horizontal, KXSpacing.screenMargin)
                .padding(.bottom, KXSpacing.md)
            }
            controls
        }
        .onChange(of: model.watchEndRequests) {
            // End pressed on the watch: finish here, then ask how hard it was.
            guard model.phase == .running else { return }
            showFinishConfirm = false
            showLeave = false
            _ = model.stop()
            showEffort = true
        }
        .confirmationDialog("Finish this run?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Finish run") {
                _ = model.stop()
                showEffort = true
            }
            Button("Keep running", role: .cancel) {}
        }
        .sheet(isPresented: $showEffort) {
            EffortSheet(title: "How hard was that run?", defaultEffort: model.typicalEffort) { effort in
                model.save(effort: effort)
                showEffort = false
                saved = true
            }
            .presentationDetents([.medium])
            .interactiveDismissDisabled()
        }
        .confirmationDialog("Leave this run?", isPresented: $showLeave, titleVisibility: .visible) {
            Button("Discard run", role: .destructive) {
                model.discard()
                // Close after the dialog has gone: iOS ignores a dismiss while the dialog is still closing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onClose() }
            }
            Button("Keep running", role: .cancel) {}
        }
    }

    /// Next direction, distance left, and an off-route warning.
    private func routeCard(_ status: RunWorkoutModel.RouteStatus) -> some View {
        HStack(spacing: KXSpacing.md) {
            Image(systemName: status.isOffRoute ? "exclamationmark.triangle.fill"
                  : status.isFinished ? "flag.checkered" : Self.directionSymbol(status.nextDirection))
                .font(.title2.weight(.semibold))
                .foregroundStyle(status.isOffRoute ? KXColor.warning : KXColor.accent)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if status.isOffRoute {
                    Text("Off route").font(KXFont.headline).foregroundStyle(KXColor.ink)
                    Text("Head back to the line on the map.").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                } else if status.isFinished {
                    Text("Route complete").font(KXFont.headline).foregroundStyle(KXColor.ink)
                } else if let next = status.nextDirection, let distance = status.distanceToNext {
                    Text(next).font(KXFont.headline).foregroundStyle(KXColor.ink).lineLimit(2)
                    Text("in \(format.shortDistance(distance))").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                } else {
                    Text("Follow the route").font(KXFont.headline).foregroundStyle(KXColor.ink)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(format.distance(status.remainingMeters)).font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
                Text("to go").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
        }
        .kxCard(status.isOffRoute ? .accent : .tinted)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("run.routeCard")
    }

    static func directionSymbol(_ text: String?) -> String {
        let lower = text?.lowercased() ?? ""
        if lower.contains("around") || lower.contains("u-turn") { return "arrow.uturn.down" }
        if lower.contains("slight left") || lower.contains("bear left") || lower.contains("keep left") { return "arrow.up.left" }
        if lower.contains("slight right") || lower.contains("bear right") || lower.contains("keep right") { return "arrow.up.right" }
        if lower.contains("left") { return "arrow.turn.up.left" }
        if lower.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }

    private func header(trailing: AnyView) -> some View {
        HStack(spacing: KXSpacing.md) {
            KXIconButton(systemImage: "xmark", accessibilityLabel: model.phase == .ready ? "Close" : "Leave run", size: 36) {
                if model.phase == .ready { onClose() } else { showLeave = true }
            }
            VStack(alignment: .leading, spacing: 0) {
                KXOverline("Running Trainer", color: KXColor.accent)
                Text(model.title).font(KXFont.headline).foregroundStyle(KXColor.ink).lineLimit(1)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, KXSpacing.screenMargin)
        .padding(.vertical, KXSpacing.sm)
    }

    private var segmentCard: some View {
        let snapshot = model.snapshot
        return VStack(alignment: .leading, spacing: KXSpacing.sm) {
            if let segment = snapshot.segment {
                HStack {
                    KXOverline(segment.kind.displayName + (segment.label.map { " · \($0)" } ?? ""), color: KXColor.accent)
                    Spacer()
                    if let remaining = snapshot.segmentRemaining {
                        Text("\(format.segmentLength(remaining)) left")
                            .font(KXFont.captionEmphasis.monospacedDigit())
                            .foregroundStyle(KXColor.ink)
                    }
                }
                KXProgressBar(value: snapshot.segmentProgress)
                if let target = segment.targetPace {
                    Text("Target \(format.paceRange(target))").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                }
                if let next = snapshot.nextSegment {
                    Text("Next: \(next.label ?? next.kind.displayName) · \(format.segmentLength(next.length))")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
            } else {
                KXOverline("Session complete", color: KXColor.success)
                Text("Keep going to cool down, or finish your run.").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            }
        }
        .kxCard()
        .accessibilityElement(children: .combine)
    }

    private var telemetryCard: some View {
        let snapshot = model.snapshot
        return VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack {
                KXOverline("Live telemetry")
                Spacer()
                if snapshot.isPaused { KXChip(text: "Paused", variant: .warning) }
                else if !snapshot.gpsAvailable { KXChip(text: "Weak GPS", systemImage: "location.slash", variant: .warning) }
                else if model.isMirroringToWatch { KXChip(text: "On Apple Watch", systemImage: "applewatch") }
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXOverline("Current pace")
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(snapshot.currentPace.map { Units.formatPace($0, units: model.units) } ?? "--:--")
                            .font(KXFont.metric)
                            .foregroundStyle(paceColor(snapshot.paceStatus))
                        Text(Units.paceUnitLabel(model.units)).font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
                    }
                    Text(statusText(snapshot.paceStatus)).font(KXFont.captionEmphasis).foregroundStyle(paceColor(snapshot.paceStatus))
                }
                .accessibilityElement(children: .combine)
                Spacer()
                KXMetric(label: "Distance", value: Units.formatDistance(meters: snapshot.distanceMeters, units: model.units),
                         unit: Units.distanceUnitLabel(model.units))
            }
            Divider()
            HStack {
                KXMetric(label: "Avg pace", value: snapshot.averagePace.map { Units.formatPace($0, units: model.units) } ?? "--:--",
                         unit: Units.paceUnitLabel(model.units), size: .small)
                Spacer()
                KXMetric(label: "Heart rate", value: snapshot.heartRate.map { "\(Int($0))" } ?? "--", unit: "bpm", size: .small)
                Spacer()
                KXMetric(label: "On target", value: snapshot.targetedSeconds > 0 ? "\(Int(snapshot.timeInTargetSeconds / snapshot.targetedSeconds * 100))" : "--",
                         unit: "%", size: .small)
            }
        }
        .kxCard()
    }

    private var pacerCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            Toggle(isOn: $model.paceCuesEnabled) {
                Label("Earphone audio pacer", systemImage: "headphones").font(KXFont.bodyEmphasis)
            }
            .tint(KXColor.accent)
            if let last = model.announcements.last {
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    KXOverline(last.isCue ? "Live pacing cue" : "Last announcement", color: last.isCue ? KXColor.accent : KXColor.inkSecondary)
                    Text("“\(last.text)”").font(KXFont.callout).foregroundStyle(KXColor.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard(model.announcements.last?.isCue == true ? .accent : .tinted)
    }

    private var controls: some View {
        HStack(spacing: KXSpacing.md) {
            Button {
                model.skipSegment()
            } label: {
                Label("Skip", systemImage: "forward.end.fill")
            }
            .buttonStyle(.kx(.outlined))
            .disabled(model.snapshot.segment == nil)
            .accessibilityLabel("Skip to next segment")

            Button {
                model.togglePause()
            } label: {
                Label(model.snapshot.isPaused ? "Resume" : "Pause", systemImage: model.snapshot.isPaused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.kx(.inverted, fullWidth: true))

            Button("Finish") { showFinishConfirm = true }
                .buttonStyle(.kx(.primary))
        }
        .padding(KXSpacing.screenMargin)
        .background(KXColor.background)
    }

    private func paceColor(_ status: PaceRange.Position?) -> Color {
        switch status {
        case .onTarget: return KXColor.success
        case .tooFast: return KXColor.accent
        case .tooSlow: return KXColor.slate
        case nil: return KXColor.ink
        }
    }

    private func statusText(_ status: PaceRange.Position?) -> String {
        switch status {
        case .onTarget: return "On target"
        case .tooFast: return "Too fast"
        case .tooSlow: return "Too slow"
        case nil: return model.snapshot.segment?.targetPace == nil ? "No target" : "Measuring…"
        }
    }
}

/// Route on a map (MapKit).
struct RouteMap: View {
    let route: [RoutePoint]
    /// A planned route, drawn underneath what's been run.
    var planned: [RouteCoordinate] = []
    var followLatest = false

    private var coordinates: [CLLocationCoordinate2D] {
        route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var plannedCoordinates: [CLLocationCoordinate2D] { planned.map(\.clCoordinate) }

    var body: some View {
        Map(position: .constant(cameraPosition), interactionModes: followLatest ? [] : .all) {
            if plannedCoordinates.count > 1 {
                MapPolyline(coordinates: plannedCoordinates)
                    .stroke(KXColor.teal.opacity(0.75), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if route.isEmpty, let start = plannedCoordinates.first {
                Annotation("Start", coordinate: start) {
                    Circle().fill(KXColor.success).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(KXColor.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let last = coordinates.last {
                Annotation("", coordinate: last) {
                    Circle().fill(KXColor.accent).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                }
            }
            if !followLatest, let first = coordinates.first {
                Annotation("Start", coordinate: first) {
                    Circle().fill(KXColor.success).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .accessibilityLabel(coordinates.isEmpty ? "Map: waiting for GPS" : "Map of your route")
    }

    private var cameraPosition: MapCameraPosition {
        if followLatest, let last = coordinates.last {
            return .camera(MapCamera(centerCoordinate: last, distance: 1200))
        }
        let all = coordinates.isEmpty ? plannedCoordinates : coordinates + plannedCoordinates
        guard !all.isEmpty else { return .automatic }
        let lats = all.map(\.latitude), lons = all.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.005, (lats.max()! - lats.min()!) * 1.4),
                                    longitudeDelta: max(0.005, (lons.max()! - lons.min()!) * 1.4))
        return .region(MKCoordinateRegion(center: center, span: span))
    }
}

/// Session effort (sRPE) after a run or workout.
struct EffortSheet: View {
    let title: String
    @State private var effort: Double
    let onSave: (Double) -> Void

    init(title: String, defaultEffort: Double, onSave: @escaping (Double) -> Void) {
        self.title = title
        _effort = State(initialValue: min(max(defaultEffort.rounded(), 1), 10))
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xl) {
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text(title).font(KXFont.title).foregroundStyle(KXColor.ink)
                Text("Your effort rating feeds your training load, which balances running and lifting.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            }
            VStack(spacing: KXSpacing.sm) {
                HStack {
                    Text("\(Int(effort))").font(KXFont.metric).foregroundStyle(KXColor.accent)
                    Text("/ 10 · \(EffortSheet.label(for: effort))").font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                    Spacer()
                }
                Slider(value: $effort, in: 1...10, step: 1)
                    .tint(KXColor.accent)
                    .accessibilityLabel("Session effort")
                    .accessibilityValue("\(Int(effort)) out of 10, \(EffortSheet.label(for: effort))")
            }
            Button("Save") { onSave(effort) }
                .buttonStyle(.kx(.primary, fullWidth: true))
        }
        .padding(KXSpacing.xl)
    }

    static func label(for effort: Double) -> String {
        switch Int(effort) {
        case ...2: return "Very easy"
        case 3...4: return "Easy"
        case 5...6: return "Moderate"
        case 7...8: return "Hard"
        case 9: return "Very hard"
        default: return "Maximal"
        }
    }
}
