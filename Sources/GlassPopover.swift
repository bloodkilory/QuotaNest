import AppKit

// 透明原生面板直接承载系统玻璃，避免 NSPopover 的底材盖住玻璃效果。
final class GlassPopover: NSPanel, NSWindowDelegate {
    private weak var anchor: NSView?
    private var anchorDismissTime: TimeInterval?
    private var closing = false
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
            if isVisible, let target = anchoredFrame(forContentSize: newValue) {
                if frame != target { setFrame(target, display: true, animate: false) }
            } else if contentRect(forFrameRect: frame).size != newValue {
                setContentSize(newValue)
            }
        }
    }
    func show(below anchor: NSView) {
        self.anchor = anchor
        anchorDismissTime = nil
        positionAtAnchor()
        makeKeyAndOrderFront(nil)
    }
    private func anchorScreenRect() -> NSRect? {
        guard let anchor, let window = anchor.window else { return nil }
        return window.convertToScreen(anchor.convert(anchor.bounds, to: nil)).insetBy(dx: -8, dy: -6)
    }
    func consumeRecentAnchorDismiss(within interval: TimeInterval = 0.4, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard let time = anchorDismissTime else { return false }
        anchorDismissTime = nil
        return now - time <= interval
    }
    private func anchoredFrame(forContentSize size: NSSize) -> NSRect? {
        guard let anchor, let window = anchor.window else { return nil }
        let frameSize = frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        var x = rect.midX - frameSize.width / 2
        var y = rect.minY - frameSize.height - 6
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            x = max(visible.minX + 8, min(x, visible.maxX - frameSize.width - 8))
            y = max(visible.minY + 8, y)
        }
        return NSRect(origin: NSPoint(x: x, y: y), size: frameSize)
    }
    private func positionAtAnchor() {
        guard let target = anchoredFrame(forContentSize: contentSize) else { return }
        if frame != target { setFrame(target, display: false, animate: false) }
    }
    override func performClose(_ sender: Any?) {
        guard !closing else { return }
        closing = true
        defer { closing = false }
        anchorDismissTime = nil
        orderOut(sender)
    }
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
    func handleResignKey(mouseLocation: NSPoint = NSEvent.mouseLocation, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isVisible, !closing else { return }
        closing = true
        defer { closing = false }
        if let rect = anchorScreenRect(), rect.contains(mouseLocation) {
            anchorDismissTime = now
        } else {
            anchorDismissTime = nil
        }
        orderOut(nil)
    }
    func windowDidResignKey(_ notification: Notification) { handleResignKey() }
}
