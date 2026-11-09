import AppKit

// 透明原生面板直接承载系统玻璃，避免 NSPopover 的底材盖住玻璃效果。
final class GlassPopover: NSPanel, NSWindowDelegate {
    private weak var anchor: NSView?
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = self
    }
    override var canBecomeKey: Bool { true }
    var isShown: Bool { isVisible }
    var contentSize: NSSize {
        get { contentRect(forFrameRect: frame).size }
        set {
            setContentSize(newValue)
            if isVisible { positionAtAnchor() }
        }
    }
    func show(below anchor: NSView) {
        self.anchor = anchor
        positionAtAnchor()
        makeKeyAndOrderFront(nil)
    }
    private func positionAtAnchor() {
        guard let anchor else { return }
        guard let window = anchor.window else { return }
        let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        var x = rect.midX - frame.width / 2
        var y = rect.minY - frame.height - 6
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            x = max(visible.minX + 8, min(x, visible.maxX - frame.width - 8))
            y = max(visible.minY + 8, y)
        }
        setFrameOrigin(NSPoint(x: x, y: y))
    }
    override func performClose(_ sender: Any?) { orderOut(sender) }
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
    func windowDidResignKey(_ notification: Notification) { orderOut(nil) }
}
