import Foundation

enum RelativeTime {
    static func short(_ date: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "\(max(s, 0))s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        if h < 24 { return "\(h)h" }
        let d = h / 24
        if d < 30 { return "\(d)d" }
        let mo = d / 30
        if mo < 12 { return "\(mo)mo" }
        return "\(mo / 12)y"
    }
}
