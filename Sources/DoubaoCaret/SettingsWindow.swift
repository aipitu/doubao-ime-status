import AppKit
import ServiceManagement

private final class SettingsDocument: NSView {
    override var isFlipped: Bool { true }
}

final class PreviewView: NSView {
    let preferences: Preferences
    private let chinese: BadgeView
    private let english: BadgeView
    init(preferences: Preferences) {
        self.preferences = preferences
        chinese = BadgeView(preferences: preferences); english = BadgeView(preferences: preferences)
        super.init(frame: .zero)
        english.mode = .english; addSubview(chinese); addSubview(english)
        wantsLayer = true; layer?.cornerRadius = 10
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func layout() {
        super.layout()
        for (badge, x) in [(chinese, bounds.width * 0.28), (english, bounds.width * 0.72)] {
            let anchor = CGRect(x: x, y: 62, width: preferences.anchor == .caret ? 2 : 0,
                                height: preferences.anchor == .caret ? 22 : 0)
            badge.frame = CGRect(origin: Placement.origin(anchor: anchor, size: badge.badgeSize,
                corner: preferences.corner, offset: preferences.offset, screen: bounds.insetBy(dx: 4, dy: 4)), size: badge.badgeSize)
            badge.needsDisplay = true
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill(); bounds.fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                                                   .foregroundColor: NSColor.secondaryLabelColor]
        ("中文                              English" as NSString).draw(at: CGPoint(x: 30, y: 12), withAttributes: attrs)
        for x in [bounds.width * 0.28, bounds.width * 0.72] {
            if preferences.anchor == .caret {
                NSColor.labelColor.setFill(); CGRect(x: x, y: 62, width: 2, height: 22).fill()
            } else {
                NSCursor.arrow.image.draw(at: CGPoint(x: x, y: 62 - NSCursor.arrow.image.size.height), from: .zero,
                                          operation: .sourceOver, fraction: 1)
            }
        }
    }
    func refresh() { needsLayout = true; needsDisplay = true }
}

final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private let preferences: Preferences
    private let preview: PreviewView
    private let diagnostics = NSTextField(wrappingLabelWithString: "")
    private var valueLabels: [String: NSTextField] = [:]
    var onPermissions: (() -> Void)?
    var onLogin: (() -> Void)?
    var diagnosticsText: (() -> String)?
    private var refreshTimer: Timer?

    init(preferences: Preferences) {
        self.preferences = preferences; preview = PreviewView(preferences: preferences)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 580, height: 730),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "豆包状态 · Settings"; window.isReleasedWhenClosed = false; window.center()
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        scroll.drawsBackground = false; window.contentView!.addSubview(scroll)
        let document = SettingsDocument(); document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20)])
        let title = NSTextField(labelWithString: "输入状态，就在注意力附近")
        title.font = .systemFont(ofSize: 20, weight: .semibold); stack.addArrangedSubview(title)
        let sub = NSTextField(labelWithString: "所有修改立即生效并自动保存。预览中的中英文同时展示。")
        sub.textColor = .secondaryLabelColor; sub.font = .systemFont(ofSize: 12); stack.addArrangedSubview(sub)
        preview.translatesAutoresizingMaskIntoConstraints = false; stack.addArrangedSubview(preview)
        preview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 150).isActive = true
        addPopup(stack, label: "显示模式", key: "anchor", items: ["Caret 优先 + Mouse fallback", "Follow Mouse"], selected: preferences.anchor.rawValue)
        addPopup(stack, label: "相对位置", key: "corner", items: ["左上", "右上", "左下", "右下"], selected: preferences.corner.rawValue)
        addSlider(stack, label: "X Offset", key: "offsetX", value: preferences.offset.x, range: -100...200)
        addSlider(stack, label: "Y Offset", key: "offsetY", value: preferences.offset.y, range: -100...200)
        let hint = NSTextField(labelWithString: "Offset 单位为 pt；正数远离锚点，负数靠近或越过锚点。")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor; stack.addArrangedSubview(hint)
        for (mode, label, key) in [(InputMode.chinese, "中文", "chinese"), (.english, "英文", "english")] {
            let field = NSTextField(string: preferences.text(mode)); field.identifier = NSUserInterfaceItemIdentifier(key + "Text")
            field.delegate = self; field.widthAnchor.constraint(equalToConstant: 130).isActive = true
            let color = NSColorWell(); color.color = preferences.color(mode); color.identifier = NSUserInterfaceItemIdentifier(key + "Color")
            color.target = self; color.action = #selector(colorChanged(_:))
            color.widthAnchor.constraint(equalToConstant: 50).isActive = true
            color.heightAnchor.constraint(equalToConstant: 26).isActive = true
            row(stack, label: label + "文字 / 颜色", controls: [field, color])
        }
        addSlider(stack, label: "字体大小", key: "fontSize", value: preferences.fontSize, range: 10...36)
        addSlider(stack, label: "透明度", key: "opacity", value: preferences.opacity, range: 0.15...1)
        addSlider(stack, label: "背景圆角", key: "radius", value: preferences.radius, range: 0...16)
        let background = NSButton(checkboxWithTitle: "显示背景", target: self, action: #selector(toggle(_:)))
        background.identifier = NSUserInterfaceItemIdentifier("background"); background.state = preferences.background ? .on : .off
        let infer = NSButton(checkboxWithTitle: "独立 Shift 推断", target: self, action: #selector(toggle(_:)))
        infer.identifier = NSUserInterfaceItemIdentifier("shiftInference"); infer.state = preferences.shiftInference ? .on : .off
        row(stack, label: "检测与外观", controls: [background, infer])
        let inferenceHint = NSTextField(wrappingLabelWithString: "若豆包未启用 Shift 切换，请关闭推断。? 表示尚无可靠状态；按 Shift 或输入拼音可触发校准。")
        inferenceHint.font = .systemFont(ofSize: 11); inferenceHint.textColor = .secondaryLabelColor
        inferenceHint.preferredMaxLayoutWidth = 530; stack.addArrangedSubview(inferenceHint)
        let permission = NSButton(title: "权限设置与更新修复…", target: self, action: #selector(permissions))
        let login = NSButton(title: "登录启动设置…", target: self, action: #selector(login))
        row(stack, label: "系统权限", controls: [permission, login])
        diagnostics.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        diagnostics.textColor = .secondaryLabelColor; diagnostics.preferredMaxLayoutWidth = 530
        stack.addArrangedSubview(diagnostics)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: Preferences.changed, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func present() {
        NSApp.activate(ignoringOtherApps: true); showWindow(nil); window?.makeKeyAndOrderFront(nil)
        updateDiagnostics()
        if refreshTimer == nil {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                if self.window?.isVisible == true { self.updateDiagnostics() }
                else { self.refreshTimer?.invalidate(); self.refreshTimer = nil }
            }
        }
    }
    private func updateDiagnostics() { diagnostics.stringValue = diagnosticsText?() ?? "" }
    private func row(_ stack: NSStackView, label: String, controls: [NSView]) {
        let caption = NSTextField(labelWithString: label); caption.font = .systemFont(ofSize: 12)
        caption.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let row = NSStackView(views: [caption] + controls); row.spacing = 10; row.alignment = .centerY
        stack.addArrangedSubview(row)
    }
    private func addPopup(_ stack: NSStackView, label: String, key: String, items: [String], selected: Int) {
        let popup = NSPopUpButton(); popup.addItems(withTitles: items); popup.selectItem(at: selected)
        popup.identifier = NSUserInterfaceItemIdentifier(key); popup.target = self; popup.action = #selector(popupChanged(_:))
        popup.widthAnchor.constraint(equalToConstant: 300).isActive = true
        row(stack, label: label, controls: [popup])
    }
    private func addSlider(_ stack: NSStackView, label: String, key: String, value: CGFloat, range: ClosedRange<Double>) {
        let slider = NSSlider(value: Double(value), minValue: range.lowerBound, maxValue: range.upperBound,
                              target: self, action: #selector(sliderChanged(_:)))
        slider.isContinuous = true; slider.identifier = NSUserInterfaceItemIdentifier(key)
        slider.widthAnchor.constraint(equalToConstant: 260).isActive = true
        let field = NSTextField(string: key == "opacity" ? String(format: "%.2f", value) : String(format: "%.0f", value))
        field.identifier = NSUserInterfaceItemIdentifier(key); field.delegate = self
        field.widthAnchor.constraint(equalToConstant: 55).isActive = true
        valueLabels[key] = field
        row(stack, label: label, controls: [slider, field])
    }
    @objc private func popupChanged(_ sender: NSPopUpButton) { preferences.set(sender.identifier!.rawValue, sender.indexOfSelectedItem) }
    @objc private func sliderChanged(_ sender: NSSlider) {
        let key = sender.identifier!.rawValue
        let v = key == "opacity" ? sender.doubleValue : sender.doubleValue.rounded()
        valueLabels[key]?.stringValue = key == "opacity" ? String(format: "%.2f", v) : String(format: "%.0f", v)
        preferences.set(key, v)
    }
    @objc private func colorChanged(_ sender: NSColorWell) { preferences.setColor(sender.identifier!.rawValue, sender.color) }
    @objc private func toggle(_ sender: NSButton) { preferences.set(sender.identifier!.rawValue, sender.state == .on) }
    @objc private func changed() { preview.refresh(); updateDiagnostics() }
    @objc private func permissions() { onPermissions?() }
    @objc private func login() { onLogin?() }
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let key = field.identifier?.rawValue else { return }
        if key.hasSuffix("Text") { preferences.set(key, String(field.stringValue.prefix(8))) }
        else if let value = Double(field.stringValue), value.isFinite {
            let range: ClosedRange<Double> = key == "opacity" ? 0.15...1 : key == "fontSize" ? 10...36 : key == "radius" ? 0...16 : -100...200
            let clamped = min(range.upperBound, max(range.lowerBound, value))
            preferences.set(key, clamped)
            // Keep the slider synchronized when editing exact offsets by keyboard.
            if let row = field.superview as? NSStackView {
                (row.arrangedSubviews.first { $0 is NSSlider } as? NSSlider)?.doubleValue = clamped
            }
        }
    }
}
