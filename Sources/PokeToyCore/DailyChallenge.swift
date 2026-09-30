import Foundation

/// The same catch round for everyone on a given day.
public enum DailyChallenge {
    /// Regular Pokémon per round (plus one legendary): enough that a 60 s round rarely sees the same one twice.
    public static let regulars = 12

    /// Days are counted on the Gregorian calendar in the local time zone, whatever calendar the user prefers.
    public static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// yyyymmdd of `date`, used as the game seed.
    public static func seed(for date: Date, calendar: Calendar = DailyChallenge.gregorian) -> UInt64 {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return UInt64((day.year ?? 0) * 10_000 + (day.month ?? 0) * 100 + (day.day ?? 0))
    }

    /// "yyyy-MM-dd" of `date`, the key for the day's best score.
    public static func key(for date: Date, calendar: Calendar = DailyChallenge.gregorian) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    /// Twelve regular Pokémon plus one legendary, picked from the complete base forms in a fixed order.
    public static func roster(from catalog: [CatalogEntry], seed: UInt64) -> [CatalogEntry] {
        let base = catalog.filter { $0.isComplete && !$0.path.contains("/") }.sorted { $0.path < $1.path }
        var rng = SplitMix64(seed: seed)
        var regular = base.filter { !Legendaries.isLegendary(path: $0.path) }
        let legendaries = base.filter { Legendaries.isLegendary(path: $0.path) }
        var picked: [CatalogEntry] = []
        while picked.count < regulars, !regular.isEmpty {
            picked.append(regular.remove(at: min(Int(rng.unit() * Double(regular.count)), regular.count - 1)))
        }
        if !legendaries.isEmpty {
            picked.append(legendaries[min(Int(rng.unit() * Double(legendaries.count)), legendaries.count - 1)])
        }
        return picked
    }
}
