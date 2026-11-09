import AppKit

enum GlassAppearance {
    static func isDark(_ appearance: NSAppearance) -> Bool { appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua }
    static func base(dark: Bool, solid: Bool) -> NSColor {
        if solid { return NSColor(white:dark ? 0.20 : 0.94,alpha:1) }
        return NSColor(white:dark ? 0.70 : 1,alpha:dark ? 0.14 : 0.32)
    }
    static func wrap(_ content: NSView, size: NSSize, cornerRadius: CGFloat = 14) -> NSView {
        let frame = NSRect(origin:.zero,size:size)
        content.frame = frame; content.autoresizingMask = [.width,.height]
        // 使用系统公开的玻璃组件；按运行时能力判断，兼容旧 SDK 和旧系统。
        if let glassType = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassType.init(frame: frame)
            glass.setValue(cornerRadius, forKey: "cornerRadius")
            glass.setValue(content, forKey: "contentView")
            return glass
        }
        let backdrop = NSVisualEffectView(frame: frame)
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = cornerRadius
        backdrop.layer?.masksToBounds = true
        backdrop.addSubview(content)
        return backdrop
    }
    static func card(_ content: NSView, width: CGFloat, height: CGFloat) -> NSView {
        let box = NSBox(); box.boxType = .custom; box.titlePosition = .noTitle
        box.cornerRadius = 10; box.borderWidth = 0.5
        box.borderColor = .separatorColor
        box.fillColor = NSColor(name:nil) { appearance in
            NSColor(white:isDark(appearance) ? 0.12 : 1,alpha:NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.65)
        }
        box.contentViewMargins = NSSize(width:8,height:8); box.contentView = content
        box.widthAnchor.constraint(equalToConstant:width).isActive = true
        box.heightAnchor.constraint(equalToConstant:height + 16).isActive = true
        return box
    }
}
