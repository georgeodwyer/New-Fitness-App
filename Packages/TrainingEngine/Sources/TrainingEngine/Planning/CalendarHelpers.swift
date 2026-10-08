import Foundation

extension Calendar {
    /// ISO weekday (Monday = 1 ... Sunday = 7) of a date.
    public func weekday(of date: Date) -> Weekday {
        let gregorian = component(.weekday, from: date) // Sunday = 1
        return Weekday(rawValue: ((gregorian + 5) % 7) + 1) ?? .monday
    }

    /// Midnight on the Monday of the week containing `date`.
    public func startOfISOWeek(for date: Date) -> Date {
        let day = startOfDay(for: date)
        let offset = weekday(of: day).rawValue - 1
        return self.date(byAdding: .day, value: -offset, to: day) ?? day
    }

    /// The date of `weekday` in the week starting `monday`.
    public func date(for weekday: Weekday, inWeekStarting monday: Date) -> Date {
        date(byAdding: .day, value: weekday.rawValue - 1, to: monday) ?? monday
    }
}

extension Weekday {
    /// The following day, wrapping Sunday → Monday (weeks repeat).
    public var next: Weekday { Weekday(rawValue: rawValue % 7 + 1) ?? .monday }
    public var previous: Weekday { Weekday(rawValue: (rawValue + 5) % 7 + 1) ?? .sunday }

    /// Days between two weekdays going around the week either way (0...3).
    public func circularDistance(to other: Weekday) -> Int {
        let diff = abs(rawValue - other.rawValue)
        return min(diff, 7 - diff)
    }
}
