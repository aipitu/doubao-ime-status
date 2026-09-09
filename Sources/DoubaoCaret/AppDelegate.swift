import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let preferences = Preferences()
    private let detector = IMEDetector()
    private let tracker = CaretTracker()
    private let monitor = InputMonitor()
    private lazy var overlay = OverlayController(preferences: preferences)
    private lazy var settings = SettingsWindowController(preferences: preferences)
    private lazy var permissionWindow = PermissionsWindowController()
    private var status: NSStatusItem!
    private var timer: Timer?
    private var shift = ShiftTracker()
    private var tickCount = 0
    private var caretReason = "鼠标 fallback"
    private var lastExternalCaret = "尚未检测其他应用，请切回编辑器输入后再查看。"
    private var sessionPaused = false
    private var permissions = (ax: false, input: false)
    private var previousEnabled = false
    private var previousAnchor: AnchorMode = .caret
    private var ignoreUntil = 0.0
    private let alphaCodes: Set<CGKeyCode> = [0,1,2,3,4,5,6,7,8,9,11,12,13,14,15,16,17,31,32,34,35,37,38,40,45,46]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        status.menu = NSMenu(); status.menu?.delegate = self
        detector.onChange = { [weak self] mode, reason in
            guard let self else { return }; self.overlay.mode = mode
            self.status.button?.toolTip = "豆包状态：\(reason)"; self.refresh()
        }
        tracker.onResult = { [weak self] result in
            guard let self else { return }; self.overlay.caret = result.rect
            self.overlay.secure = result.secure || IsSecureEventInputEnabled()
            self.caretReason = result.reason; self.overlay.refresh()
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                self.lastExternalCaret = result.reason
            }
        }
        monitor.onEvent = { [weak self] in self?.handle($0) }
        settings.onPermissions = { [weak self] in self?.requestPermissions() }
        permissionWindow.onRecheck = { [weak self] in
            guard let self else { return }
            self.permissions = (AXIsProcessTrusted(), CGPreflightListenEventAccess())
            self.configureServices()
        }
        permissionWindow.inputMonitorRunning = { [weak self] in self?.monitor.keyboardAvailable ?? false }
        settings.onLogin = { SMAppService.openSystemSettingsLoginItems() }
        settings.diagnosticsText = { [weak self] in self?.diagnostics() ?? "" }
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: Preferences.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(inputSourceChanged),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspace.addObserver(self, selector: #selector(environmentChanged), name: name, object: nil)
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(self, selector: #selector(processChanged), name: name, object: nil)
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(self, selector: #selector(pauseSession), name: name, object: nil)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(resumeSession), name: name, object: nil)
        }
        permissions = (AXIsProcessTrusted(), CGPreflightListenEventAccess())
        preferencesChanged()
        if CommandLine.arguments.contains("--permissions") {
            permissionWindow.present()
        } else if !CommandLine.arguments.contains("--smoke-test") && !UserDefaults.standard.bool(forKey: "hasOpened") {
            UserDefaults.standard.set(true, forKey: "hasOpened"); settings.present()
        }
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
        }
    }
    @objc private func preferencesChanged() {
        if preferences.enabled != previousEnabled {
            previousEnabled = preferences.enabled; configureServices()
        }
        if preferences.anchor != previousAnchor {
            previousAnchor = preferences.anchor; activateTracker()
        }
        refresh()
    }
    private func configureServices() {
        timer?.invalidate(); timer = nil; shift.reset()
        ignoreUntil = ProcessInfo.processInfo.systemUptime + 1
        let active = preferences.enabled && !sessionPaused
        detector.setEnabled(active)
        if active {
            monitor.start()
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            t.tolerance = 0.2; RunLoop.main.add(t, forMode: .common); timer = t
        } else { monitor.stop() }
        activateTracker(); refresh()
    }
    private func activateTracker() {
        tracker.activate(pid: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,
            enabled: preferences.enabled && !sessionPaused && preferences.anchor == .caret)
    }
    private func tick() {
        let fresh = (ax: AXIsProcessTrusted(), input: CGPreflightListenEventAccess())
        if fresh.ax != permissions.ax || fresh.input != permissions.input {
            permissions = fresh; detector.invalidate("权限变化，重新校准")
            monitor.start(); detector.discoverProcess(); activateTracker()
        }
        let secure = IsSecureEventInputEnabled()
        if overlay.secure != secure && secure {
            shift.reset(); detector.invalidate("安全输入，暂停状态推断")
        }
        // Each caret query rechecks a single focused element. No tree walk.
        if preferences.anchor == .caret { tracker.request() }
        else { overlay.secure = secure }
        detector.refreshSource()
        tickCount += 1
        if tickCount % 2 == 0 { detector.requestProbe() }
        if tickCount % 5 == 0 { detector.discoverProcess() }
        overlay.refresh()
    }
    private func handle(_ event: InputMonitor.Event) {
        guard preferences.enabled, !sessionPaused else { return }
        let now = ProcessInfo.processInfo.systemUptime
        switch event {
        case .move:
            if preferences.anchor == .mouse || overlay.caret == nil { overlay.scheduleMove() }
        case .mouse, .scroll:
            shift.otherActivity(); tracker.request(); detector.verifyBurst()
        case .interrupted:
            shift.reset(); detector.invalidate("输入事件中断，等待校准")
        case .key(let code, let flags):
            shift.otherActivity(); tracker.request()
            if !flags.contains(.maskCommand) && !flags.contains(.maskControl) && !flags.contains(.maskAlternate)
                && alphaCodes.contains(code) && !IsSecureEventInputEnabled() { detector.alphaKey() }
        case .flags(let code, let flags):
            guard now >= ignoreUntil, !IsSecureEventInputEnabled() else {
                shift.reset(); detector.invalidate("修饰键同步中"); return
            }
            detector.refreshSource()
            if code == 56 || code == 60 {
                let other = !flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskAlphaShift, .maskSecondaryFn]).isEmpty
                let context = detector.source.id + ":" + String(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
                if shift.changed(pressed: flags.contains(.maskShift), otherModifiers: other, time: now, context: context) {
                    detector.standaloneShift(infer: preferences.shiftInference)
                } else if !flags.contains(.maskShift) {
                    if shift.uncertain { detector.invalidate("Shift 事件不确定，等待校准") }
                    detector.verifyBurst()
                }
            } else {
                shift.otherActivity()
                if code == 57 { detector.invalidate("Caps Lock 变化，等待校准") }
                detector.verifyBurst()
            }
        }
    }
    @objc private func environmentChanged() {
        shift.reset(); detector.focusChanged(); activateTracker()
    }
    @objc private func inputSourceChanged() {
        shift.reset(); detector.refreshSource(); activateTracker(); detector.verifyBurst()
    }
    @objc private func processChanged() { detector.discoverProcess() }
    @objc private func pauseSession() {
        sessionPaused = true; overlay.paused = true; configureServices()
    }
    @objc private func resumeSession() {
        sessionPaused = false; overlay.paused = false; configureServices()
    }
    private func refresh() {
        status.button?.title = preferences.enabled ? preferences.text(detector.mode) : "○"
        overlay.refresh()
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        func item(_ title: String, _ selector: Selector?, checked: Bool = false) {
            let i = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            i.target = self; i.state = checked ? .on : .off; menu.addItem(i)
        }
        item(preferences.enabled ? "Disable · 停用" : "Enable · 启用", #selector(toggleEnabled))
        item("Settings… · 设置", #selector(showSettings))
        item("Launch at Login · 登录启动", #selector(toggleLogin), checked: SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator())
        item("状态：\(detector.reason)", nil)
        item("位置：\(caretReason)", nil)
        item("复制上次应用的光标诊断", #selector(copyCaretDiagnostics))
        item("校准为中文", #selector(calibrateChinese))
        item("校准为英文", #selector(calibrateEnglish))
        menu.addItem(.separator())
        item("权限设置与更新修复…", #selector(requestPermissions))
        item("Quit · 退出", #selector(quit))
    }
    private func diagnostics() -> String {
        "辅助功能：\(AXIsProcessTrusted() ? "已授权" : "未授权")  输入监听：\(monitor.keyboardAvailable ? "运行中" : "未运行")\n"
            + "状态：\(detector.reason)\n上次应用光标：\(lastExternalCaret)"
    }
    @objc private func copyCaretDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("DoubaoCaret \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "")\n"
            + "模式：\(preferences.anchor)\n" + diagnostics(), forType: .string)
    }
    @objc private func toggleEnabled() { preferences.set("enabled", !preferences.enabled) }
    @objc private func showSettings() { settings.present() }
    @objc private func calibrateChinese() { detector.calibrate(.chinese) }
    @objc private func calibrateEnglish() { detector.calibrate(.english) }
    @objc private func requestPermissions() {
        permissionWindow.present()
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            let alert = NSAlert(); alert.messageText = "无法修改登录启动"
            alert.informativeText = "请先将应用移到 /Applications 后重试。\n\(error.localizedDescription)"
            alert.runModal()
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop(); timer?.invalidate(); tracker.shutdown()
    }
}
