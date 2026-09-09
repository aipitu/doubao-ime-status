import AppKit

final class IndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class BadgeView: NSView {
    let preferences: Preferences
    var mode: InputMode = .chinese { didSet { needsDisplay = true } }
    init(preferences: Preferences) { self.preferences = preferences; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    var badgeSize: CGSize {
        let width = (preferences.text(mode) as NSString).size(withAttributes: attributes).width
        return CGSize(width: ceil(width) + 10, height: ceil(preferences.fontSize * 1.35) + 6)
    }
    private var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedSystemFont(ofSize: preferences.fontSize, weight: .medium),
         .foregroundColor: preferences.color(mode)]
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(preferences.opacity)
        if preferences.background {
            NSColor(calibratedWhite: 0.08, alpha: 0.94).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: preferences.radius, yRadius: preferences.radius).fill()
        }
        let text = preferences.text(mode) as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class OverlayController {
    private let panel: IndicatorPanel
    private let badge: BadgeView
    private let preferences: Preferences
    var caret: CGRect?
    var secure = false
    var paused = false
    var mode: InputMode = .unknown
    private var movePending = false

    init(preferences: Preferences) {
        self.preferences = preferences; badge = BadgeView(preferences: preferences)
        panel = IndicatorPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true; panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isReleasedWhenClosed = false; panel.animationBehavior = .none
        panel.contentView = badge
        panel.setAccessibilityElement(false)
    }
    func scheduleMove() {
        guard !movePending else { return }; movePending = true
        // Event-driven coalescing. No display timer runs while the mouse is idle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in
            self?.movePending = false; self?.refresh()
        }
    }
    func refresh() {
        guard preferences.enabled, !paused, !secure, mode != .inactive else { panel.orderOut(nil); return }
        badge.mode = mode
        let size = badge.badgeSize
        let mouse = NSEvent.mouseLocation
        let anchor = preferences.anchor == .caret ? (caret ?? CGRect(origin: mouse, size: .zero)) : CGRect(origin: mouse, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }
        let origin = Placement.origin(anchor: anchor, size: size, corner: preferences.corner,
                                      offset: preferences.offset, screen: screen?.visibleFrame)
        let frame = CGRect(origin: origin, size: size)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        badge.needsDisplay = true
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}
