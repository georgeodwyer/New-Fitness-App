import SwiftUI
import TrainingEngine

/// Every training pace as a ladder, slowest at the top: a bar for where each sits from
/// slower to faster, coloured from easy to hard, and the range. Edit opens the zones screen.
struct YourPacesCard: View {
    let profile: AthleteProfile
    let profileModel: UserProfileModel?
    let format: DisplayFormat

    @State private var editing = false

    private struct Row: Identifiable {
        let zone: PaceZone
        let range: PaceRange
        let color: Color
        var id: PaceZone { zone }
    }

    /// Slowest first; colours run from easy (grey) through the run colour to hard (red).
    private var rows: [Row] {
        let zones = PaceZones(profile: profile)
        let ranges = PaceZonesView.order.map { ($0, zones.range(for: $0)) }
            .sorted { ($0.1.fastest.secondsPerKm + $0.1.slowest.secondsPerKm) > ($1.1.fastest.secondsPerKm + $1.1.slowest.secondsPerKm) }
        let ramp: [Color] = [KXColor.other, KXColor.run, KXColor.run, KXColor.success, KXColor.warning, KXColor.warning,
                             KXColor.danger, KXColor.danger, KXColor.danger]
        return ranges.enumerated().map { index, item in
            Row(zone: item.0, range: item.1, color: ramp[min(index * ramp.count / max(ranges.count, 1), ramp.count - 1)])
        }
    }

    var body: some View {
        let rows = rows
        let slowest = (rows.map(\.range.slowest.secondsPerKm).max() ?? 400) + 10
        let fastest = (rows.map(\.range.fastest.secondsPerKm).min() ?? 200) - 10
        let span = max(slowest - fastest, 1)
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack {
                KXOverline("Your paces")
                Spacer()
                Button("Edit") { editing = true }
                    .font(KXFont.captionEmphasis)
                    .foregroundStyle(KXColor.ink)
                    .padding(.horizontal, KXSpacing.md)
                    .padding(.vertical, KXSpacing.xs)
                    .background(KXColor.surfaceTint, in: Capsule())
                    .accessibilityHint("Shows every pace and how to make them more accurate")
            }
            ForEach(rows) { row in
                HStack(spacing: KXSpacing.sm) {
                    Text(row.zone.displayName)
                        .font(KXFont.bodyEmphasis)
                        .foregroundStyle(KXColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 104, alignment: .leading)
                    GeometryReader { geo in
                        // Faster paces sit further right.
                        let left = geo.size.width * (slowest - row.range.slowest.secondsPerKm) / span
                        let width = max(geo.size.width * 0.09, geo.size.width * (row.range.slowest.secondsPerKm - row.range.fastest.secondsPerKm) / span)
                        ZStack(alignment: .leading) {
                            Capsule().fill(KXColor.surfaceTint)
                            Capsule().fill(row.color)
                                .frame(width: width)
                                .offset(x: min(left, geo.size.width - width))
                        }
                    }
                    .frame(height: 10)
                    .accessibilityHidden(true)
                    Text("\(Units.formatPace(row.range.fastest, units: format.units))–\(Units.formatPace(row.range.slowest, units: format.units))")
                        .font(KXFont.number(17, relativeTo: .body))
                        .foregroundStyle(KXColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 84, alignment: .trailing)
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.zone.displayName): \(Units.formatPace(row.range.fastest, units: format.units)) to \(Units.formatPace(row.range.slowest, units: format.units)) per \(Units.distanceUnitLabel(format.units))")
            }
            HStack(spacing: KXSpacing.sm) {
                Color.clear.frame(width: 104, height: 1)
                HStack {
                    Text("slower")
                    Spacer()
                    Text("faster")
                }
                Text("per \(Units.distanceUnitLabel(format.units))").frame(width: 84, alignment: .trailing)
            }
            .font(KXFont.caption)
            .foregroundStyle(KXColor.inkTertiary)
            .accessibilityHidden(true)
            Divider().overlay(KXColor.border)
            Text(paceSource(profile, format: format) + " · they update as your runs get faster")
                .font(KXFont.caption)
                .foregroundStyle(KXColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .kxCard()
        .accessibilityIdentifier("progress.paces")
        .sheet(isPresented: $editing) {
            PaceZonesView(profile: profile, profileModel: profileModel, format: format)
        }
    }
}
