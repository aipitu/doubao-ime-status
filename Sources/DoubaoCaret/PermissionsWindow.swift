import AppKit
import ApplicationServices

/// Permission grants remain in System Settings. This window offers navigation,
/// a live operational check and an explicitly copied, app-scoped reset command.
final class PermissionsWindowController: NSWindowController {
    var onRecheck: (() -> Void)?
    var inputMonitorRunning: (() -> Bool)?
    private let status = NSTextField(wrappingLabelWithString: "")
    private var timer: Timer?

    init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 480),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "豆包状态 · 权限与更新修复"
        window.isReleasedWhenClosed = false; window.center()
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)])
        let heading = NSTextField(labelWithString: "两项权限，一处管理")
        heading.font = .systemFont(ofSize: 20, weight: .semibold); stack.addArrangedSubview(heading)
        status.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        status.preferredMaxLayoutWidth = 450; stack.addArrangedSubview(status)
        let buttons = NSStackView(views: [
            NSButton(title: "1. 打开辅助功能", target: self, action: #selector(openAccessibility)),
            NSButton(title: "2. 打开输入监控", target: self, action: #selector(openInputMonitoring))])
        buttons.spacing = 12; stack.addArrangedSubview(buttons)
        let controls = NSStackView(views: [
            NSButton(title: "重新检测权限", target: self, action: #selector(recheck)),
            NSButton(title: "在 Finder 中显示应用", target: self, action: #selector(revealApplication))])
        controls.spacing = 12; stack.addArrangedSubview(controls)
        let explanation = NSTextField(wrappingLabelWithString:
            "更新后开关已打开却仍不可用？测试包的签名身份可能已变化。可重置本应用的旧授权，再在系统设置中允许；无需逐条查找和删除。")
        explanation.preferredMaxLayoutWidth = 450; stack.addArrangedSubview(explanation)
        stack.addArrangedSubview(NSButton(title: "复制本应用的权限修复命令", target: self, action: #selector(copyRepairCommand)))
        let note = NSTextField(wrappingLabelWithString:
            "命令只重置豆包状态的辅助功能和输入监控，不影响其他应用。系统授权仍需手动确认。建议始终从 /Applications 运行。")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 450; stack.addArrangedSubview(note)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func present() {
        NSApp.activate(ignoringOtherApps: true); showWindow(nil); window?.makeKeyAndOrderFront(nil)
        refresh()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                if self.window?.isVisible == true { self.refresh() }
                else { self.timer?.invalidate(); self.timer = nil }
            }
        }
    }
    private func refresh() {
        status.stringValue = "辅助功能：\(AXIsProcessTrusted() ? "已授权" : "未授权或旧授权失效")\n"
            + "输入监控：\(CGPreflightListenEventAccess() ? "系统报告已授权" : "未授权或旧授权失效")\n"
            + "输入事件监听：\(inputMonitorRunning?() == true ? "运行中" : "未运行（停用时属正常）")"
    }
    @objc private func openAccessibility() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func openInputMonitoring() {
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
    @objc private func recheck() { onRecheck?(); refresh() }
    @objc private func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
    @objc private func copyRepairCommand() {
        // Quote for POSIX shells, including app paths containing apostrophes.
        let path = "'" + Bundle.main.bundleURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = """
        /usr/bin/tccutil reset Accessibility local.doubao-caret
        /usr/bin/tccutil reset ListenEvent local.doubao-caret
        /usr/bin/open \(path) --args --permissions
        """
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string)
        let alert = NSAlert(); alert.messageText = "修复命令已复制"
        alert.informativeText = "请先通过菜单退出豆包状态，再在终端粘贴执行。命令会清除本应用的两项旧授权并重新打开权限窗口，之后请重新允许访问。"
        if let window { alert.beginSheetModal(for: window, completionHandler: nil) }
    }
}
