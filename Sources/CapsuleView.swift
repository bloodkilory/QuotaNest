import AppKit

// 透明按钮保留辅助功能操作，鼠标由胶囊整体的点击手势处理。
private final class CapsuleActionButton: NSButton {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class CapsuleView: NSView {
    private(set) var lastActionEventType: Int = -1
    private(set) var lastClickX: CGFloat = -1
    var provider: QuotaProviderID = .codex { didSet { needsDisplay = true } }
    var text = "—" { didSet { needsDisplay = true } }
    var remaining: Double? { didSet { needsDisplay = true } }
    var stale = false { didSet { needsDisplay = true } }
    var showsWallet = false { didSet { needsDisplay = true } }
    var periodText = "1w" { didSet { needsDisplay = true } }
    var canSwitchPeriod = false { didSet { periodButton.isEnabled = canSwitchPeriod; needsDisplay = true } }
    var periodAction: (() -> Void)?
    let detailButton: NSButton = CapsuleActionButton()
    let periodButton: NSButton = CapsuleActionButton()
    var dividerX: CGFloat { bounds.width - 16 }
    var action: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
        for button in [detailButton, periodButton] {
            button.title = ""; button.isBordered = false; button.isTransparent = true
            button.target = self; addSubview(button)
        }
        detailButton.action = #selector(openDetails)
        periodButton.action = #selector(switchPeriod)
        periodButton.setAccessibilityLabel(L("切换额度周期"))
        periodButton.isEnabled = false
        detailButton.autoresizingMask = [.width, .height]
        periodButton.autoresizingMask = [.minXMargin, .height]
        if #unavailable(macOS 27.0) {
            addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked(_:))))
        }
        layoutButtons()
    }
    required init?(coder: NSCoder) { fatalError() }
    // 外层跟随菜单栏高度，玻璃保持 18 点高，避免拉伸后两端变扁。
    func configureStatusItem(_ item: NSStatusItem) {
        frame.size = NSSize(width: 64, height: 18)
        let container = NSView(frame: bounds)
        let surface = GlassAppearance.wrap(self, size: bounds.size, cornerRadius: 9)
        surface.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        container.addSubview(surface)
        item.view = container
        item.highlightMode = false
        item.target = self
        item.action = #selector(statusActivated)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func statusActivated() {
        activateStatusItem(for: NSApp.currentEvent?.type, atScreenPoint: NSEvent.mouseLocation)
    }
    func activateStatusItem(for eventType: NSEvent.EventType?, atScreenPoint point: NSPoint) {
        lastActionEventType = eventType.map { Int($0.rawValue) } ?? -1
        // 新菜单栏动作不更新 currentEvent；只识别明确的键盘操作，其余按真实指针分区。
        if #available(macOS 27.0, *),
           eventType != nil && eventType != .keyDown && eventType != .keyUp {
            activate(atScreenPoint: point)
        } else {
            openDetails()
        }
    }
    @objc private func clicked(_ gesture: NSClickGestureRecognizer) {
        activate(atX: gesture.location(in: self).x)
    }
    // macOS 27 的菜单栏动作给出合成中心点，使用真实鼠标位置换算。
    func activate(atScreenPoint point: NSPoint) {
        guard let window else { return }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        guard bounds.contains(local) else { return }
        activate(atX: local.x)
    }
    // 鼠标坐标按胶囊位置换算，右侧 16 点始终对应周期按钮。
    func activate(atX x: CGFloat) {
        lastClickX = x
        if x >= dividerX {
            periodButton.performClick(nil)
        } else {
            detailButton.performClick(nil)
        }
    }
    @objc private func openDetails() { action?() }
    @objc private func switchPeriod() { if canSwitchPeriod { periodAction?() } }
    private func layoutButtons() {
        detailButton.frame = CGRect(x: 0, y: 0, width: dividerX, height: bounds.height)
        periodButton.frame = CGRect(x: dividerX, y: 0, width: 16, height: bounds.height)
    }
    override func layout() { super.layout(); layoutButtons() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    private var capsuleRect: CGRect {
        CGRect(x: 0, y: (bounds.height - 18) / 2, width: bounds.width, height: 18)
    }
    var accentColor: NSColor {
        switch provider {
        case .codex: return NSColor(srgbRed: 0.20, green: 0.44, blue: 0.39, alpha: 1)
        case .claude: return NSColor(srgbRed: 0.63, green: 0.34, blue: 0.24, alpha: 1)
        case .zcode: return NSColor(srgbRed: 0.27, green: 0.39, blue: 0.61, alpha: 1)
        case .antigravity: return NSColor(srgbRed: 0.23, green: 0.39, blue: 0.65, alpha: 1)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = capsuleRect
        let shape = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        let dark = GlassAppearance.isDark(effectiveAppearance)
        let solid = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let ink: NSColor = dark ? .white : NSColor(white:0.12,alpha:1)
        GlassAppearance.base(dark:dark,solid:solid).setFill()
        shape.fill()

        if let remaining, remaining.isFinite {
            let fraction = min(100, max(0, remaining)) / 100
            let color: NSColor
            if stale { color = NSColor.gray.withAlphaComponent(solid ? 0.65 : 0.35) }
            else { color = accentColor.withAlphaComponent(solid ? 0.85 : 0.78) }
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            color.setFill()
            CGRect(x: rect.minX, y: rect.minY, width: (dividerX - rect.minX) * fraction, height: rect.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // 高光与下沿明暗形成玻璃厚度，避免只剩一层半透明底色。
        if !solid {
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            NSGradient(starting: NSColor.white.withAlphaComponent(dark ? 0.20 : 0.36),
                       ending: NSColor.black.withAlphaComponent(0.06))?.draw(in: rect, angle: -90)
            NSGraphicsContext.restoreGraphicsState()
        }
        if showsWallet { ProviderMark.drawDeepSeek(in:CGRect(x:rect.minX + 3,y:rect.midY - 5,width:10,height:10)) }
        else { ProviderMark.draw(provider,in:CGRect(x:rect.minX + 3,y:rect.midY - 5,width:10,height:10),tint:ink) }

        var fontSize: CGFloat = 9
        while (text as NSString).size(withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:fontSize,weight:.semibold)]).width > 30 && fontSize > 6.5 { fontSize -= 0.5 }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: ink
        ]
        let label = text as NSString
        let size = label.size(withAttributes: attrs)
        let textRect = CGRect(x: rect.minX + 15, y: rect.minY, width: dividerX - rect.minX - 16, height: rect.height)
        let separator = NSBezierPath()
        separator.move(to: CGPoint(x: dividerX, y: rect.minY + 3))
        separator.line(to: CGPoint(x: dividerX, y: rect.maxY - 3))
        ink.withAlphaComponent(0.22).setStroke()
        separator.lineWidth = 0.5; separator.stroke()
        let periodAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: periodText.count > 3 ? 6 : 7.5, weight: .medium),
            .foregroundColor: ink.withAlphaComponent(canSwitchPeriod ? 1 : 0.60)
        ]
        let periodSize = (periodText as NSString).size(withAttributes: periodAttrs)
        (periodText as NSString).draw(at: CGPoint(x: (dividerX + rect.maxX) / 2 - periodSize.width / 2, y: rect.midY - periodSize.height / 2), withAttributes: periodAttrs)
        label.draw(at: CGPoint(x: textRect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }
}
