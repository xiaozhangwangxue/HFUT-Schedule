import Foundation

/// Calendar date parsing is called for each lesson during layout. Creating a
/// DateFormatter for every date can block navigation for a whole semester.
enum CampusDateCodec {
    private static let cache: NSCache<NSString, NSDate> = {
        let cache = NSCache<NSString, NSDate>(); cache.countLimit = 4096; return cache
    }()
    static func date(_ text: String, calendar: Calendar) -> Date? {
        let key = "\(calendar.identifier)|\(calendar.timeZone.identifier)|\(text)" as NSString
        if let value = cache.object(forKey: key) { return value as Date }
        let bytes = Array(text.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ [4, 7].contains($0.offset) || (48...57).contains($0.element) }),
              let year = Int(text.prefix(4)), let month = Int(text.dropFirst(5).prefix(2)), let day = Int(text.suffix(2)),
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        cache.setObject(date as NSDate, forKey: key); return date
    }
}
