import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError("FAIL: \(message)") }
}
let anchor = CGRect(x: 100, y: 100, width: 2, height: 20)
let size = CGSize(width: 20, height: 24)
let offset = CGPoint(x: 10, y: 8)
for (corner, expected) in [(Corner.topLeft, CGPoint(x: 70, y: 128)), (.topRight, CGPoint(x: 112, y: 128)),
                           (.bottomLeft, CGPoint(x: 70, y: 68)), (.bottomRight, CGPoint(x: 112, y: 68))] {
    check(Placement.origin(anchor: anchor, size: size, corner: corner, offset: offset, screen: nil) == expected, "corner \(corner)")
}
check(Placement.origin(anchor: .zero, size: size, corner: .bottomLeft, offset: offset,
                       screen: CGRect(x: 0, y: 0, width: 100, height: 100)) == .zero, "clamp lower edge")
check(Placement.origin(anchor: CGRect(x: -100, y: 200, width: 0, height: 0), size: size,
    corner: .topRight, offset: offset, screen: CGRect(x: -200, y: 0, width: 200, height: 200)) == CGPoint(x: -90, y: 176), "negative monitor / top clamp")
let rect = Placement.appKitRect(CGRect(x: -50, y: -100, width: 2, height: 20), primaryHeight: 900)
check(rect == CGRect(x: -50, y: 980, width: 2, height: 20), "monitor above primary")
let container = CGRect(x: 0, y: 0, width: 500, height: 500)
check(Placement.validCaret(anchor, within: container, screens: [container]), "valid caret")
check(!Placement.validCaret(CGRect(x: 20, y: 20, width: 300, height: 20), within: container, screens: [container]), "reject line rectangle")
check(!Placement.validCaret(CGRect(x: 900, y: 20, width: 0, height: 20), within: container, screens: [container]), "reject stale/offscreen")
check(!Placement.validCaret(.zero, within: container, screens: [container]), "reject zero rectangle")
check(Placement.validCaret(CGRect(x: 20, y: 20, width: 12, height: 22), within: container, screens: [container]), "accept block caret wider than 8pt")
check(Placement.validCaret(anchor, within: nil, screens: [container]), "accept AX caret when element does not expose frame")
check(!Placement.validCaret(CGRect(x: 20, y: 20, width: 50, height: 22), within: container, screens: [container]), "reject text span")
check(!Placement.validCaret(anchor, within: CGRect(x: 200, y: 200, width: 100, height: 100), screens: [container]), "reject caret outside owning window")
check(ModeEvidence.afterFocus(.chinese, sameSource: true, isDoubao: true) == .chinese, "focus preserves known Chinese")
check(ModeEvidence.afterFocus(.english, sameSource: true, isDoubao: true) == .english, "focus preserves known English")
check(ModeEvidence.afterFocus(.chinese, sameSource: false, isDoubao: true) == .unknown, "new input source still requires calibration")
check(ModeEvidence.afterFocus(.unknown, sameSource: true, isDoubao: true) == .unknown, "focus never guesses unknown state")
check(ModeEvidence.afterFocus(.english, sameSource: false, isDoubao: false) == .inactive, "hide on non-Doubao input source")
check(ModeEvidence.exactLabel(" 英\n") == .english, "exact English")
check(ModeEvidence.exactLabel("中") == .chinese, "exact Chinese")
for label in ["英文标点", "英语词典", "中文设置", "", "A", "中文", "中英"] {
    check(ModeEvidence.exactLabel(label) == nil, "reject settings text \(label)")
}
check(ModeEvidence.toggled(.unknown) == .unknown, "unknown is never guessed")
check(ModeEvidence.toggled(.chinese) == .english, "known toggle")
var shift = ShiftTracker()
func press(_ time: Double, _ context: String = "app1", _ other: Bool = false) {
    check(!shift.changed(pressed: true, otherModifiers: other, time: time, context: context), "press alone doesn't toggle")
}
press(1)
check(shift.changed(pressed: false, otherModifiers: false, time: 1.1, context: "app1"), "clean tap")
press(1.2)
check(!shift.changed(pressed: false, otherModifiers: false, time: 1.3, context: "app1"), "debounce")
press(2); shift.otherActivity()
check(!shift.changed(pressed: false, otherModifiers: false, time: 2.1, context: "app1"), "Shift letter / click / scroll")
press(3)
check(!shift.changed(pressed: false, otherModifiers: false, time: 3.1, context: "app2"), "focus/source race")
check(shift.uncertain, "focus/source race loses certainty")
press(4, "app1", true)
check(!shift.changed(pressed: false, otherModifiers: false, time: 4.1, context: "app1"), "modifier chord")
press(5)
check(!shift.changed(pressed: false, otherModifiers: false, time: 6.1, context: "app1"), "long hold")
check(shift.uncertain, "long hold loses certainty")
press(7); press(7.1)
check(!shift.changed(pressed: false, otherModifiers: false, time: 7.2, context: "app1"), "both Shift keys")
press(8); shift.reset()
check(!shift.changed(pressed: false, otherModifiers: false, time: 8.1, context: "app1"), "tap interruption")
print("PASS: \(checks) state-machine and geometry checks")
