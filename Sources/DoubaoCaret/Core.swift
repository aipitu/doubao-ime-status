import Foundation

enum InputMode: String { case chinese, english, unknown, inactive }
enum AnchorMode: Int, CaseIterable { case caret, mouse }
enum Corner: Int, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
}

/// All geometry here is in AppKit points, with positive Y pointing up.
enum Placement {
    static func origin(anchor: CGRect, size: CGSize, corner: Corner,
                       offset: CGPoint, screen: CGRect?) -> CGPoint {
        var p = CGPoint(x: corner.isLeft ? anchor.minX - size.width - offset.x : anchor.maxX + offset.x,
                        y: corner.isTop ? anchor.maxY + offset.y : anchor.minY - size.height - offset.y)
        if let s = screen {
            p.x = max(s.minX, min(p.x, s.maxX - size.width))
            p.y = max(s.minY, min(p.y, s.maxY - size.height))
        }
        return p
    }

    static func validCaret(_ r: CGRect, within element: CGRect?, screens: [CGRect]) -> Bool {
        r.origin.x.isFinite && r.origin.y.isFinite && r.width.isFinite && r.height.isFinite
            && r.width >= 0 && r.width <= min(40, max(8, r.height)) && r.height >= 4 && r.height <= 100
            && (element == nil || element!.insetBy(dx: -2, dy: -2).contains(CGPoint(x: r.midX, y: r.midY)))
            && screens.contains { $0.intersects(r.insetBy(dx: -1, dy: 0)) }
    }

    static func appKitRect(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}

/// A pure state machine. A Shift chord is never a language toggle.
struct ShiftTracker {
    private var down: (time: Double, context: String)?
    private var dirty = false
    private var lastToggle = -Double.infinity
    private(set) var uncertain = false
    mutating func reset() { down = nil; dirty = false; uncertain = false }
    mutating func otherActivity() { if down != nil { dirty = true } }
    mutating func changed(pressed: Bool, otherModifiers: Bool, time: Double, context: String) -> Bool {
        uncertain = false
        if pressed {
            if down == nil { down = (time, context); dirty = otherModifiers }
            else { dirty = true } // both Shift keys or unmatched events
            return false
        }
        guard let start = down else { uncertain = true; return false }
        let clean = !dirty && !otherModifiers && start.context == context
            && time - start.time <= 1 && time - start.time >= 0
            && time - lastToggle >= 0.35
        let lostCertainty = !dirty && !otherModifiers && !clean
        reset(); uncertain = lostCertainty
        if clean { lastToggle = time }
        return clean
    }
}

enum ModeEvidence {
    static func afterFocus(_ mode: InputMode, sameSource: Bool, isDoubao: Bool) -> InputMode {
        guard isDoubao else { return .inactive }
        return sameSource && (mode == .chinese || mode == .english) ? mode : .unknown
    }
    static func exactLabel(_ text: String) -> InputMode? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "中": return .chinese
        case "英": return .english
        default: return nil
        }
    }
    static func toggled(_ mode: InputMode) -> InputMode {
        mode == .chinese ? .english : mode == .english ? .chinese : .unknown
    }
}
