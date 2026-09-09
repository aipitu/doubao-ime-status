import AppKit
import Carbon

struct InputSource: Equatable {
    static let doubaoBundle = "com.bytedance.inputmethod.doubaoime"
    let id: String
    let bundle: String
    var isDoubao: Bool { bundle == Self.doubaoBundle || id.hasPrefix(Self.doubaoBundle + ".") }
    static func current() -> InputSource {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return InputSource(id: "", bundle: "")
        }
        func property(_ key: CFString) -> String {
            guard let ptr = TISGetInputSourceProperty(source, key) else { return "" }
            return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? String ?? ""
        }
        return InputSource(id: property(kTISPropertyInputSourceID), bundle: property(kTISPropertyBundleID))
    }
}

/// Adapted detection strategy from Jian Zhou's MIT input-indicator project.
/// See THIRD_PARTY_LICENSES/input-indicator.txt and docs/RESEARCH.md.
/// Never scan the IME's whole AX tree, never infer English from missing candidates.
final class IMEProbe {
    struct Evidence { let mode: InputMode; let reason: String }
    let subscription = AXSubscription()
    private var pid: pid_t = 0
    private var app: AXUIElement?
    // All state below is confined to accessibilityQueue.
    func attach(pid: pid_t) {
        guard self.pid != pid || app == nil else { return }
        subscription.stop(); self.pid = pid; app = nil
        guard pid > 0, AXIsProcessTrusted() else { return }
        app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app!, 0.025)
        subscription.start(pid: pid, notifications: [kAXWindowCreatedNotification,
            kAXCreatedNotification, kAXLayoutChangedNotification])
    }
    func stop() { subscription.stop(); pid = 0; app = nil }
    func read(allowCandidate: Bool) -> Evidence? {
        guard pid > 0, let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        var candidate = false
        var labels = Set<String>()
        let deadline = ProcessInfo.processInfo.systemUptime + 0.06
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0 >= 2_147_483_000,
                (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: bounds) else { continue }
            let small = (15...50).contains(rect.width) && (15...50).contains(rect.height)
            if small, let app, ProcessInfo.processInfo.systemUptime < deadline {
                var hit: AXUIElement?
                if AXUIElementCopyElementAtPosition(app, Float(rect.midX), Float(rect.midY), &hit) == .success,
                    let hit {
                    var owner: pid_t = 0
                    if AXUIElementGetPid(hit, &owner) == .success, owner == pid {
                        var budget = 20
                        collect(hit, depth: 0, budget: &budget, deadline: deadline, labels: &labels)
                    }
                }
            } else if allowCandidate && rect.width >= 100 && rect.width <= 1200
                        && rect.height >= 24 && rect.height <= 500 {
                candidate = true
            }
        }
        if labels.count == 1, let label = labels.first, let mode = ModeEvidence.exactLabel(label) {
            return Evidence(mode: mode, reason: "豆包 AX 提示：\(label)")
        }
        // Conflicting labels are not resolved by guessing.
        if labels.isEmpty && candidate { return Evidence(mode: .chinese, reason: "豆包候选窗 · 中文正向证据") }
        return nil
    }
    private func collect(_ element: AXUIElement, depth: Int, budget: inout Int,
                         deadline: Double, labels: inout Set<String>) {
        guard depth <= 3, budget > 0, ProcessInfo.processInfo.systemUptime < deadline else { return }
        budget -= 1; AXUIElementSetMessagingTimeout(element, 0.015)
        for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return }
            if let text = AX.value(element, key) as? String, let mode = ModeEvidence.exactLabel(text) {
                labels.insert(mode == .chinese ? "中" : "英")
            }
        }
        // Copy at most eight children, rather than fetching an arbitrarily large array.
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count) == .success,
              count > 0, ProcessInfo.processInfo.systemUptime < deadline else { return }
        var result: CFArray?
        guard AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, min(count, 8), &result) == .success,
            let children = result as? [AXUIElement] else { return }
        for child in children { collect(child, depth: depth + 1, budget: &budget, deadline: deadline, labels: &labels) }
    }
}

/// Main-thread state and scheduling. Idle fallback is one window-list read / 2s;
/// notifications and short verification bursts handle fast changes.
final class IMEDetector {
    var onChange: ((InputMode, String) -> Void)?
    private(set) var mode: InputMode = .unknown
    private(set) var reason = "等待豆包状态证据"
    private(set) var source = InputSource.current()
    private let probe = IMEProbe()
    private var generation = 0
    private var inFlight = false
    private var enabled = false
    private var lastAlpha = -Double.infinity
    private var lastShift = -Double.infinity
    private var nextProbe = 0.0
    private var imePID: pid_t = 0
    private var alphaCheck: DispatchWorkItem?
    private var burstGeneration = 0

    init() { probe.subscription.onChange = { [weak self] in self?.requestProbe() } }
    func setEnabled(_ value: Bool) {
        enabled = value; invalidate("重新检测")
        if value { refreshSource(); discoverProcess(); verifyBurst() }
        else { accessibilityQueue.async { [probe] in probe.stop() }; imePID = 0 }
    }
    func refreshSource() {
        let fresh = InputSource.current()
        if fresh != source { source = fresh; invalidate("输入源已切换"); verifyBurst() }
        if !source.isDoubao { set(.inactive, "当前不是豆包输入法") }
    }
    func discoverProcess() {
        guard enabled else { return }
        let pid = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == InputSource.doubaoBundle
        }?.processIdentifier ?? 0
        if pid != imePID { imePID = pid; invalidate("豆包进程已变化") }
        accessibilityQueue.async { [probe] in probe.attach(pid: pid) }
    }
    func invalidate(_ message: String) {
        generation += 1; burstGeneration += 1
        lastAlpha = -.infinity; alphaCheck?.cancel(); alphaCheck = nil
        set(source.isDoubao ? .unknown : .inactive, message)
    }
    func calibrate(_ value: InputMode) {
        guard source.isDoubao else { return }
        generation += 1; set(value, "手动校准（未改变输入法）")
    }
    func focusChanged() {
        let fresh = InputSource.current()
        let next = ModeEvidence.afterFocus(mode, sameSource: fresh == source, isDoubao: fresh.isDoubao)
        source = fresh
        // Cancel evidence captured in the old context, but a focus event alone
        // is not evidence that the IME's global mode has changed.
        generation += 1; burstGeneration += 1
        lastAlpha = -.infinity; alphaCheck?.cancel(); alphaCheck = nil
        set(next, next == .chinese || next == .english ? "最近已知状态 · 切焦点后复核" : "等待当前输入源状态证据")
        verifyBurst()
    }
    func standaloneShift(infer: Bool) {
        guard enabled, source.isDoubao else { return }
        generation += 1; lastShift = ProcessInfo.processInfo.systemUptime
        set(infer ? ModeEvidence.toggled(mode) : .unknown,
            infer ? "独立 Shift 推断 · 等待 AX 校验" : "等待 AX 校验")
        verifyBurst()
    }
    func alphaKey() {
        guard enabled, source.isDoubao else { return }
        lastAlpha = ProcessInfo.processInfo.systemUptime
        // Throttle, not debounce: continuous typing still generates evidence.
        guard alphaCheck == nil else { return }
        let job = DispatchWorkItem { [weak self] in self?.alphaCheck = nil; self?.requestProbe() }
        alphaCheck = job; DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: job)
    }
    func verifyBurst() {
        guard enabled, source.isDoubao else { return }
        burstGeneration += 1; let token = burstGeneration
        for delay in [0.06, 0.16, 0.35, 0.65] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.burstGeneration == token else { return }; self.requestProbe()
            }
        }
    }
    func requestProbe() {
        let now = ProcessInfo.processInfo.systemUptime
        guard enabled, source.isDoubao, !inFlight, now >= nextProbe else { return }
        inFlight = true; nextProbe = now + 0.05
        let token = generation
        let candidate = now - lastAlpha < 1 && now - lastShift > 1
        accessibilityQueue.async { [self] in
            let evidence = probe.read(allowCandidate: candidate)
            DispatchQueue.main.async { [self] in
                inFlight = false
                guard token == generation, enabled, source.isDoubao, let evidence else { return }
                set(evidence.mode, evidence.reason)
            }
        }
    }
    private func set(_ value: InputMode, _ reason: String) {
        guard mode != value || self.reason != reason else { return }
        mode = value; self.reason = reason; onChange?(value, reason)
    }
}
