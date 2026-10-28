import SwiftUI
import TrainingEngine

/// A run screen the runner built on their phone: a layout of metric slots.
struct CustomScreenView: View {
    let screen: WatchScreen
    let input: WatchMetricInputs

    var body: some View {
        let slots = screen.slots
        VStack(spacing: 5) {
            switch screen.layout {
            case .one:
                Spacer(minLength: 0)
                hero(slots[0], size: 64, centred: true)
                Spacer(minLength: 0)
            case .oneTwo:
                hero(slots[0], size: 52)
                Spacer(minLength: 0)
                HStack(spacing: 5) { cell(slots[1]); cell(slots[2]) }
            case .oneFour:
                hero(slots[0], size: 46)
                HStack(spacing: 5) { cell(slots[1]); cell(slots[2]) }
                HStack(spacing: 5) { cell(slots[3]); cell(slots[4]) }
            case .threeRows:
                ForEach(0..<3, id: \.self) { cell(slots[$0], size: 28) }
            case .sixSmall:
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 5) { cell(slots[row * 2], size: 21); cell(slots[row * 2 + 1], size: 21) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
    }

    /// The big number at the top.
    private func hero(_ metric: WatchMetric, size: CGFloat, centred: Bool = false) -> some View {
        let reading = metric.reading(input)
        return VStack(alignment: centred ? .center : .leading, spacing: 0) {
            WatchOverline(metric.label)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(reading.value)
                    .font(WatchFont.number(reading.isText ? size * 0.5 : size))
                    .foregroundStyle(WatchColor.tone(reading.tone))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !reading.unit.isEmpty && !centred {
                    Text(reading.unit.uppercased()).font(WatchFont.unit).foregroundStyle(WatchColor.inkSecondary)
                }
            }
            if centred && !reading.unit.isEmpty {
                Text(reading.unit.uppercased()).font(WatchFont.unit).foregroundStyle(WatchColor.inkSecondary)
            }
            if let zone = reading.zone { WatchZoneBar(zone: zone) }
        }
        .frame(maxWidth: .infinity, alignment: centred ? .center : .leading)
    }

    /// A smaller slot in a rounded box.
    private func cell(_ metric: WatchMetric, size: CGFloat = 23) -> some View {
        let reading = metric.reading(input)
        return VStack(alignment: .leading, spacing: 0) {
            WatchOverline(metric.label)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(reading.value)
                    .font(WatchFont.number(reading.isText ? min(size, 17) : size))
                    .foregroundStyle(WatchColor.tone(reading.tone))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !reading.unit.isEmpty && !reading.isText {
                    Text(reading.unit.uppercased()).font(WatchFont.unit).foregroundStyle(WatchColor.inkSecondary).lineLimit(1)
                }
            }
            if let zone = reading.zone { WatchZoneBar(zone: zone) }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(WatchColor.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
