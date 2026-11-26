import AppKit
import QuartzCore

enum GlassAppearance {
    static func isDark(_ appearance: NSAppearance) -> Bool { appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua }
    static func base(dark: Bool, solid: Bool) -> NSColor {
        if solid { return NSColor(white:dark ? 0.20 : 0.94,alpha:1) }
        return NSColor(white:dark ? 0.70 : 1,alpha:dark ? 0.14 : 0.32)
    }
    static let glassTint = NSColor(name: nil) { appearance in
        let dark = isDark(appearance)
        let alpha: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 0.95 : 0.50
        return NSColor(white: dark ? 0.12 : 1.0, alpha: alpha)
    }
    static func wrap(_ content: NSView, size: NSSize, cornerRadius: CGFloat = 14, interactive: Bool = false) -> NSView {
        let frame = NSRect(origin:.zero,size:size)
        content.frame = frame; content.autoresizingMask = [.width,.height]
        // 使用系统公开的玻璃组件；按运行时能力判断，兼容旧 SDK 和旧系统。
        if let glassType = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassType.init(frame: frame)
            glass.setValue(cornerRadius, forKey: "cornerRadius")
            // NSGlassEffectViewStyleClear (1) + 50% 淡色 tint：保留液态玻璃质感并收敛至约 50% 透明度。
            if glass.responds(to: NSSelectorFromString("setStyle:")) {
                glass.setValue(1, forKey: "style")
            }
            if glass.responds(to: NSSelectorFromString("setTintColor:")) {
                glass.setValue(glassTint, forKey: "tintColor")
            }
            if glass.responds(to: NSSelectorFromString("setEffectIsInteractive:")) {
                glass.setValue(interactive, forKey: "effectIsInteractive")
            }
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
    @discardableResult
    static func replaceContent(in surface: NSView, with content: NSView, size: NSSize) -> Bool {
        let frame = NSRect(origin: .zero, size: size)
        var replaced = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.frame = frame
        content.autoresizingMask = [.width, .height]
        if let glassType = NSClassFromString("NSGlassEffectView"), surface.isKind(of: glassType) {
            surface.setValue(content, forKey: "contentView")
            replaced = true
        } else if surface is NSVisualEffectView {
            surface.subviews.forEach { $0.removeFromSuperview() }
            surface.addSubview(content)
            replaced = true
        }
        CATransaction.commit()
        return replaced
    }
    static func card(_ content: NSView, width: CGFloat, height: CGFloat) -> NSView {
        let box = NSBox(); box.boxType = .custom; box.titlePosition = .noTitle
        box.cornerRadius = 10; box.borderWidth = 0.5
        box.borderColor = .separatorColor
        box.fillColor = NSColor(name:nil) { appearance in
            let dark = isDark(appearance)
            return NSColor(white:dark ? 0.12 : 1,alpha:NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : (dark ? 0.18 : 0.28))
        }
        box.contentViewMargins = NSSize(width:8,height:8); box.contentView = content
        box.widthAnchor.constraint(equalToConstant:width).isActive = true
        box.heightAnchor.constraint(equalToConstant:height + 16).isActive = true
        return box
    }
}
