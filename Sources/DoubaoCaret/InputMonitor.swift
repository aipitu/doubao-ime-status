import AppKit
import Carbon

final class InputMonitor {
    enum Event { case key(CGKeyCode, CGEventFlags), flags(CGKeyCode, CGEventFlags), mouse, move, scroll, interrupted }
    var onEvent: ((Event) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var mouseFallback: Any?
    private var local: Any?
    private(set) var keyboardAvailable = false

    func start() {
        stop()
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown,
            .otherMouseDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        if CGPreflightListenEventAccess() {
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    let monitor = Unmanaged<InputMonitor>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        monitor.onEvent?(.interrupted)
                        if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    } else { monitor.handle(type, event) }
                    return Unmanaged.passUnretained(event)
                }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        }
        if let tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true); keyboardAvailable = true
        } else {
            // Mouse monitoring does not require keystroke access.
            mouseFallback = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged,
                .rightMouseDragged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] e in
                if e.type == .mouseMoved || e.type == .leftMouseDragged || e.type == .rightMouseDragged { self?.onEvent?(.move) }
                else if e.type == .scrollWheel { self?.onEvent?(.scroll) }
                else { self?.onEvent?(.mouse) }
            }
            local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] e in
                self?.onEvent?(e.type == .mouseMoved ? .move : .mouse); return e
            }
        }
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) {
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown: onEvent?(.key(code, event.flags))
        case .flagsChanged: onEvent?(.flags(code, event.flags))
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged: onEvent?(.move)
        case .scrollWheel: onEvent?(.scroll)
        default: onEvent?(.mouse)
        }
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let mouseFallback { NSEvent.removeMonitor(mouseFallback) }
        if let local { NSEvent.removeMonitor(local) }
        tap = nil; source = nil; mouseFallback = nil; local = nil; keyboardAvailable = false
    }
}
