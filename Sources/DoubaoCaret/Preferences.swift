import AppKit

final class Preferences {
    static let changed = Notification.Name("DoubaoCaretPreferencesChanged")
    private let defaults = UserDefaults.standard
    init() {
        defaults.register(defaults: ["enabled": true, "anchor": 0, "corner": 1,
            "offsetX": 10.0, "offsetY": 8.0, "chineseText": "中", "englishText": "A",
            "chineseColor": "70D6AE", "englishColor": "8DBBFF", "fontSize": 15.0,
            "opacity": 0.9, "background": true, "radius": 5.0, "shiftInference": true])
    }
    func set(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.changed, object: self)
    }
    var enabled: Bool { defaults.bool(forKey: "enabled") }
    var anchor: AnchorMode { AnchorMode(rawValue: defaults.integer(forKey: "anchor")) ?? .caret }
    var corner: Corner { Corner(rawValue: defaults.integer(forKey: "corner")) ?? .topRight }
    var offset: CGPoint { CGPoint(x: number("offsetX", -100...200), y: number("offsetY", -100...200)) }
    var fontSize: CGFloat { number("fontSize", 10...36) }
    var opacity: CGFloat { number("opacity", 0.15...1) }
    var background: Bool { defaults.bool(forKey: "background") }
    var radius: CGFloat { number("radius", 0...16) }
    var shiftInference: Bool { defaults.bool(forKey: "shiftInference") }
    func number(_ key: String, _ range: ClosedRange<Double>) -> CGFloat {
        let v = defaults.double(forKey: key)
        return CGFloat(v.isFinite ? min(range.upperBound, max(range.lowerBound, v)) : range.lowerBound)
    }
    func text(_ mode: InputMode) -> String {
        guard mode == .chinese || mode == .english else { return mode == .unknown ? "?" : "—" }
        let value = defaults.string(forKey: mode == .chinese ? "chineseText" : "englishText") ?? ""
        return value.isEmpty ? (mode == .chinese ? "中" : "A") : String(value.prefix(8))
    }
    func color(_ mode: InputMode) -> NSColor {
        guard mode == .chinese || mode == .english else { return .secondaryLabelColor }
        let hex = defaults.string(forKey: mode == .chinese ? "chineseColor" : "englishColor") ?? ""
        let value = UInt32(hex, radix: 16) ?? 0xFFFFFF
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    func setColor(_ key: String, _ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        set(key, String(format: "%02X%02X%02X", Int(rgb.redComponent * 255),
                        Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255)))
    }
}
