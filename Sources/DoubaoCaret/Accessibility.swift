import AppKit
import ApplicationServices

/// Shared serial queue keeps cross-process AX calls away from the event tap/UI.
let accessibilityQueue = DispatchQueue(label: "local.doubao-caret.accessibility", qos: .utility)

enum AX {
    static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    static func element(_ element: AXUIElement, _ key: String) -> AXUIElement? {
        guard let ref = value(element, key), CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }
    static func unpack<T>(_ ref: CFTypeRef?, type: AXValueType, into result: inout T) -> Bool {
        guard let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return false }
        let v = ref as! AXValue
        guard AXValueGetType(v) == type else { return false }
        return withUnsafeMutablePointer(to: &result) { AXValueGetValue(v, type, $0) }
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        var point = CGPoint.zero, size = CGSize.zero
        guard unpack(value(element, kAXPositionAttribute), type: .cgPoint, into: &point),
              unpack(value(element, kAXSizeAttribute), type: .cgSize, into: &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}

/// The observer owns no UI. All methods are confined to accessibilityQueue;
/// callbacks on the main runloop enqueue work through onChange.
final class AXSubscription {
    private var observer: AXObserver?
    private var registrations: [(AXUIElement, String)] = []
    var onChange: (() -> Void)?
    func start(pid: pid_t, notifications: [String]) {
        stop()
        var ref: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            Unmanaged<AXSubscription>.fromOpaque(context).takeUnretainedValue().onChange?()
        }
        guard AXObserverCreate(pid, callback, &ref) == .success, let ref else { return }
        observer = ref
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.04)
        for n in notifications { add(app, notification: n) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(ref), .commonModes)
    }
    func add(_ element: AXUIElement, notification: String) {
        guard let observer else { return }
        if AXObserverAddNotification(observer, element, notification as CFString,
            Unmanaged.passUnretained(self).toOpaque()) == .success {
            registrations.append((element, notification))
        }
    }
    func removeElement(_ element: AXUIElement) {
        guard let observer else { return }
        for (e, n) in registrations where CFEqual(e, element) {
            AXObserverRemoveNotification(observer, e, n as CFString)
        }
        registrations.removeAll { CFEqual($0.0, element) }
    }
    func stop() {
        if let observer {
            for (e, n) in registrations { AXObserverRemoveNotification(observer, e, n as CFString) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        registrations.removeAll(); observer = nil
    }
}

final class CaretTracker {
    struct Result { let rect: CGRect?; let secure: Bool; let reason: String }
    var onResult: ((Result) -> Void)?
    private let subscription = AXSubscription()
    private var app: AXUIElement?
    private var focused: AXUIElement?
    private var pid: pid_t = 0
    private var generation = 0
    private var pending = false
    private var active = false
    private var screens: [CGRect] = []
    private var primaryHeight: CGFloat = 0
    private var targetLabel = ""
    private var manualAX = ""
    private var manualAXApp: AXUIElement?

    // Only opt in the editor processes we know are Electron. Restore an observed
    // false value when leaving the app; never disable support owned by another client.
    private func restoreManualAccessibility() {
        if let root = manualAXApp {
            AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanFalse)
        }
        manualAXApp = nil
    }

    init() { subscription.onChange = { [weak self] in self?.request() } }

    func shutdown() {
        accessibilityQueue.sync { subscription.stop(); restoreManualAccessibility() }
    }

    // Main thread: invalidate visible geometry immediately on focus/Space changes.
    func activate(pid: pid_t, enabled: Bool) {
        generation += 1
        let token = generation
        onResult?(Result(rect: nil, secure: false, reason: "等待当前输入框"))
        let height = NSScreen.screens.first?.frame.height ?? 0
        let frames = NSScreen.screens.map { $0.frame }
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid=\(pid)"
        accessibilityQueue.async { [self] in
            if self.pid == pid && active == enabled && app != nil && AXIsProcessTrusted() {
                screens = frames; primaryHeight = height
                sample(token: token); return
            }
            restoreManualAccessibility()
            subscription.stop(); focused = nil; app = nil
            targetLabel = bundle; manualAX = ""
            self.pid = pid; active = enabled; screens = frames; primaryHeight = height
            if enabled && AXIsProcessTrusted() && pid > 0 {
                let root = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(root, 0.12); app = root
                if ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92"].contains(bundle) {
                    let previous = AX.value(root, "AXManualAccessibility") as? Bool
                    if previous != true {
                        let error = AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                        manualAX = " · Electron AX=\(error.rawValue)"
                        if error == .success && previous == false { manualAXApp = root }
                    }
                }
                subscription.start(pid: pid, notifications: [kAXFocusedUIElementChangedNotification,
                    kAXFocusedWindowChangedNotification, kAXWindowMovedNotification,
                    kAXWindowResizedNotification, kAXSelectedTextChangedNotification])
            }
            sample(token: token)
        }
    }
    func request() {
        // Coalescing is on main; at most one AX query is pending or running.
        guard !pending else { return }; pending = true
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in
            guard let self else { return }
            accessibilityQueue.async {
                self.sample(token: token)
                DispatchQueue.main.async { self.pending = false }
            }
        }
    }
    private func sample(token: Int) {
        let reading = readCaret()
        let result = Result(rect: reading.rect, secure: reading.secure,
                            reason: "\(targetLabel) · \(reading.reason)\(manualAX)")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            self.onResult?(result)
        }
    }
    private func readCaret() -> Result {
        func fallback(_ reason: String, secure: Bool = false) -> Result {
            Result(rect: nil, secure: secure, reason: reason)
        }
        guard active else { return fallback("鼠标 · Caret 优先未启用") }
        guard AXIsProcessTrusted() else { return fallback("鼠标 · 辅助功能未授权，请在系统设置重新添加本应用") }
        guard let app else { return fallback("鼠标 · 目标应用 AX 尚未初始化") }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.12)
        // A non-nil app result may be a wrapper window, while system-wide returns
        // the actual text field. Try both rather than letting the first mask the second.
        var candidates: [AXUIElement] = []
        var focusErrors: [String] = []
        for root in [app, system] {
            var ref: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &ref)
            focusErrors.append(String(error.rawValue))
            var current: AXUIElement?
            if let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() { current = (ref as! AXUIElement) }
            for _ in 0..<4 {
                guard let element = current, !candidates.contains(where: { CFEqual($0, element) }) else { break }
                candidates.append(element)
                current = AX.element(element, kAXFocusedUIElementAttribute)
            }
        }
        guard !candidates.isEmpty else { return fallback("鼠标 · FocusedUIElement app/system=\(focusErrors.joined(separator: "/"))") }
        var failure = "鼠标 · 无可用 caret"
        for element in candidates.reversed() {
            let result = readElement(element, app: app)
            if result.rect != nil || result.secure { return result }
            failure = result.reason
        }
        return fallback(failure)
    }

    private func readElement(_ element: AXUIElement, app: AXUIElement) -> Result {
        let role = AX.value(element, kAXRoleAttribute) as? String ?? "无角色"
        func fallback(_ reason: String, secure: Bool = false) -> Result {
            Result(rect: nil, secure: secure, reason: "鼠标 · \(role) · \(reason)")
        }
        var owner: pid_t = 0
        guard AXUIElementGetPid(element, &owner) == .success, owner == pid else { return fallback("鼠标 · 焦点已变化") }
        AXUIElementSetMessagingTimeout(element, 0.04)
        if focused == nil || !CFEqual(focused!, element) {
            if let old = focused { subscription.removeElement(old) }
            focused = element
            for n in [kAXSelectedTextChangedNotification, kAXValueChangedNotification,
                      kAXUIElementDestroyedNotification] { subscription.add(element, notification: n) }
        }
        if (AX.value(element, kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole {
            return fallback("安全输入框 · 隐藏指示器", secure: true)
        }
        // Virtual editor textareas can have a 1x1 or absent frame. Validate the
        // actual AX caret against its owning window, not that hidden textarea.
        let window = AX.element(element, kAXWindowAttribute) ?? AX.element(app, kAXFocusedWindowAttribute)
        let container = window.flatMap { AX.frame($0) } ?? AX.frame(element)
        func accept(_ ref: CFTypeRef?, method: String) -> Result? {
            var raw = CGRect.zero
            guard AX.unpack(ref, type: .cgRect, into: &raw) else { return nil }
            let rect = Placement.appKitRect(raw, primaryHeight: primaryHeight)
            let bounds = container.map { Placement.appKitRect($0, primaryHeight: primaryHeight) }
            guard Placement.validCaret(rect, within: bounds, screens: screens) else { return nil }
            return Result(rect: rect, secure: false, reason: "Caret · \(role) · \(method)")
        }
        var range = CFRange()
        var rangeRef: CFTypeRef?
        let rangeError = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        var detail = "SelectedTextRange=\(rangeError.rawValue)"
        if AX.unpack(rangeRef, type: .cfRange, into: &range) {
            guard range.location >= 0, range.length == 0 else { return fallback("选区不是插入点：length=\(range.length)") }
            if let parameter = AXValueCreate(.cfRange, &range) {
                var bounds: CFTypeRef?
                let error = AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                                        parameter, &bounds)
                if error == .success, let result = accept(bounds, method: "AXBoundsForRange") { return result }
                var raw = CGRect.zero
                if AX.unpack(bounds, type: .cgRect, into: &raw) {
                    detail = "BoundsForRange=\(error.rawValue)，矩形=\(raw) 校验未通过"
                } else { detail = "BoundsForRange=\(error.rawValue)" }
            }
        }
        // Chromium/WebKit may expose a text-marker selection instead of CFRange.
        // Query its length first: bounds of selected text are not a caret.
        // Attribute names are optional, version-dependent AX protocol extensions;
        // no private framework symbols, text contents or tree searches are used.
        if let marker = AX.value(element, "AXSelectedTextMarkerRange") {
            var length: CFTypeRef?
            let lengthError = AXUIElementCopyParameterizedAttributeValue(element, "AXLengthForTextMarkerRange" as CFString, marker, &length)
            if lengthError == .success, (length as? NSNumber)?.intValue == 0 {
                var bounds: CFTypeRef?
                let error = AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForTextMarkerRange" as CFString, marker, &bounds)
                if error == .success, let result = accept(bounds, method: "AXBoundsForTextMarkerRange") { return result }
                detail += "，TextMarkerBounds=\(error.rawValue)"
            } else { detail += "，TextMarkerLength=\(lengthError.rawValue)" }
        }
        return fallback(detail)
    }
}
