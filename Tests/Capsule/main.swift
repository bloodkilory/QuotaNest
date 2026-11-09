import AppKit
useTestLanguage()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
func bitmap(_ width: Int, _ height: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}
func render(_ amount: Double?, stale: Bool = false, dark: Bool = false) -> NSBitmapImageRep {
    let rep = bitmap(128, 48)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: 2, y: 2)
    let view = CapsuleView(frame: NSRect(x: 0, y: 0, width: 64, height: 24))
    view.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
    view.remaining = amount; view.stale = stale; view.text = ""
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
func black(_ image: NSBitmapImageRep, _ x: Int) -> Bool {
    let c = image.colorAt(x: x * 2, y: 24)!.usingColorSpace(.deviceRGB)!
    return max(c.redComponent, c.greenComponent, c.blueComponent) < 0.01
}
// Sample away from the provider mark and rounded edge; validate actual rendered pixels.
assert(!black(render(0), 40), "glass capsule has a light-adaptive base instead of solid black")
func filled(_ amount: Double?, _ x: Int, stale: Bool = false, dark: Bool = false) -> Bool {
    let c = render(amount,stale:stale,dark:dark).colorAt(x:x * 2,y:24)!.usingColorSpace(.deviceRGB)!
    let base = render(nil,dark:dark).colorAt(x:x * 2,y:24)!.usingColorSpace(.deviceRGB)!
    return abs(c.redComponent - base.redComponent) + abs(c.greenComponent - base.greenComponent) + abs(c.blueComponent - base.blueComponent) > 0.08
}
for dark in [false,true] {
    assert(!filled(0,40,dark:dark) && filled(100,40,dark:dark))
    assert(filled(50,22,dark:dark) && !filled(50,28,dark:dark))
    assert(filled(75,34,dark:dark) && !filled(75,40,dark:dark))
    assert(!filled(-10,40,dark:dark) && filled(110,40,dark:dark))
    assert(!filled(nil,40,dark:dark) && !filled(.nan,40,dark:dark))
    assert(filled(50,22,stale:true,dark:dark) && !filled(50,28,stale:true,dark:dark))
    assert(GlassAppearance.base(dark:dark,solid:true).alphaComponent == 1)
    // 填充色不能过度透出壁纸，否则换背景就会发灰或变色。
    let fill = render(100, dark: dark).colorAt(x: 80, y: 24)!.usingColorSpace(.deviceRGB)!
    assert(fill.alphaComponent > 0.75, "quota fill must remain legible over different wallpapers")
    let glass = render(nil, dark: dark)
    let top = glass.colorAt(x: 80, y: 14)!.usingColorSpace(.deviceRGB)!
    let bottom = glass.colorAt(x: 80, y: 34)!.usingColorSpace(.deviceRGB)!
    let reducedTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    let increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    if reducedTransparency || increasedContrast {
        assert(top.alphaComponent > 0.99 && bottom.alphaComponent > 0.99,
               "accessibility solid background must be opaque")
        assert(abs(top.redComponent - bottom.redComponent) < 0.01 &&
               abs(top.greenComponent - bottom.greenComponent) < 0.01 &&
               abs(top.blueComponent - bottom.blueComponent) < 0.01,
               "accessibility solid background must remain uniform")
    } else {
        assert(top.redComponent - bottom.redComponent > 0.06,
               "glass highlight: dark=\(dark), top=\(top), bottom=\(bottom)")
    }
}
print("PASS glass capsule: light/dark 0/50/75/100%, clamping, unknown, stale and reduced transparency")
// 检查系统玻璃和实际胶囊内容叠加后的像素。
for dark in [false, true] {
    let view = CapsuleView(frame: NSRect(x: 0, y: 0, width: 64, height: 37))
    let surface = GlassAppearance.wrap(view, size: view.bounds.size)
    let window = NSWindow(contentRect: surface.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = surface
    view.text = ""
    surface.layoutSubtreeIfNeeded()
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    func sample() -> NSColor {
        // 系统玻璃需要可见窗口参与合成，不能把离屏缓存当作屏幕结果。
        surface.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let image = surface.bitmapImageRepForCachingDisplay(in: surface.bounds)!
        surface.cacheDisplay(in: surface.bounds, to: image)
        return image.colorAt(x: image.pixelsWide * 40 / 64, y: image.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
    }
    view.remaining = 100
    let full = sample()
    assert(full.greenComponent - full.redComponent > 0.08, "native glass full: dark=\(dark), color=\(full), container=\(type(of: surface)), visible=\(window.isVisible), size=\(surface.bounds.size)")
    view.remaining = nil
    let empty = sample()
    assert(abs(empty.greenComponent - empty.redComponent) < 0.03, "native glass empty: dark=\(dark), color=\(empty), container=\(type(of: surface))")
    view.remaining = 100
    view.provider = .claude
    let claude = sample()
    assert(claude.redComponent - claude.greenComponent > 0.08, "native glass Claude: dark=\(dark), color=\(claude), container=\(type(of: surface))")
}
print("PASS light/dark native glass composition after quota and provider changes")
let rep = bitmap(900, 965)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(srgbRed: 0.94, green: 0.94, blue: 0.92, alpha: 1).setFill()
CGRect(x: 0, y: 0, width: 900, height: 965).fill()
func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor = .black) {
    (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color])
}
label("QuotaNest · Menu bar", x: 35, y: 913, size: 24)
label("Actual rendering · 3× · sample quotas", x: 35, y: 887, size: 13, color: .darkGray)
let amounts: [Double?] = [100, 50, 8, nil]
for (row, provider) in QuotaProviderID.allCases.enumerated() {
    let y = CGFloat(790 - row * 105)
    label(provider.title, x: 35, y: y + 49, size: 13, color: .darkGray)
    for (col, amount) in amounts.enumerated() {
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: CGFloat(30 + col * 215), y: y - 15)
        ctx.scaleBy(x: 3, y: 3)
        let view = CapsuleView(frame: NSRect(x: 0, y: 0, width: 64, height: 24))
        view.appearance = NSAppearance(named:.aqua)
        view.provider = provider; view.remaining = amount
        view.periodText = col % 2 == 0 ? "5h" : "1w"; view.canSwitchPeriod = amount != nil
        view.text = amount.map { String(format: "%.0f%%", $0) } ?? "—"
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
}
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/capsule-preview.png"))

let interactive = CapsuleView(frame: CGRect(x: 0, y: 0, width: 64, height: 24))
interactive.canSwitchPeriod = true
// 菜单栏高度改变后，按钮必须立即覆盖新区域，不能等待下一次布局。
for height in [22.0, 37.0, 40.0, 24.0] {
    interactive.frame.size = NSSize(width: 64, height: height)
    for y in [1.0, height / 2, height - 1] {
        assert(interactive.hitTest(NSPoint(x: 56, y: y)) === interactive,
               "capsule gesture must cover the full menu bar height immediately after resizing")
        assert(interactive.hitTest(NSPoint(x: 24, y: y)) === interactive)
    }
}
var details = 0, switches = 0
interactive.action = { details += 1 }; interactive.periodAction = { switches += 1 }
interactive.detailButton.performClick(nil)
interactive.periodButton.performClick(nil)
assert(details == 1 && switches == 1)
interactive.canSwitchPeriod = false
interactive.periodButton.performClick(nil)
assert(switches == 1)
assert(interactive.detailButton.frame.maxX == interactive.periodButton.frame.minX)
assert(interactive.periodButton.frame.maxX == 64)
// 复现真实 macOS 27 事件：系统给出中心点，而鼠标实际在右侧。
let host = NSWindow(contentRect: NSRect(x: 1076, y: 949, width: 80, height: 33), styleMask: .borderless, backing: .buffered, defer: false)
interactive.frame = NSRect(x: 8, y: 5.5, width: 64, height: 22)
host.contentView!.addSubview(interactive)
interactive.canSwitchPeriod = true
interactive.activate(atScreenPoint: NSPoint(x: 1142.05078125, y: 966.74609375))
assert(details == 1 && switches == 2, "real right-side pointer must switch period instead of opening details")
interactive.activate(atScreenPoint: NSPoint(x: 1116, y: 966.74609375))
assert(details == 2 && switches == 2)
interactive.canSwitchPeriod = false
interactive.activate(atScreenPoint: NSPoint(x: 1142.05078125, y: 966.74609375))
assert(details == 2 && switches == 2)
interactive.canSwitchPeriod = true
interactive.activate(atScreenPoint: NSPoint(x: 1078, y: 966.74609375))
interactive.activate(atScreenPoint: NSPoint(x: 1152, y: 966.74609375))
assert(details == 2 && switches == 2, "system padding outside the visible capsule must not trigger an action")
if #available(macOS 27.0, *) {
    interactive.activateStatusItem(for: .appKitDefined, atScreenPoint: NSPoint(x: 1142.05078125, y: 966.74609375))
    assert(details == 2 && switches == 3, "macOS 27 appKitDefined pointer action must reach the period switch")
    interactive.activateStatusItem(for: .mouseEntered, atScreenPoint: NSPoint(x: 1142.05078125, y: 966.74609375))
    assert(details == 2 && switches == 4, "stale currentEvent must not discard a native status action")
    interactive.activateStatusItem(for: .keyDown, atScreenPoint: NSPoint(x: 1142.05078125, y: 966.74609375))
    interactive.activateStatusItem(for: nil, atScreenPoint: NSPoint(x: 1142.05078125, y: 966.74609375))
    assert(details == 4 && switches == 4, "keyboard and accessibility actions must still open details")
}
let colors = QuotaProviderID.allCases.map { provider -> NSColor in interactive.provider = provider; return interactive.accentColor }
assert(colors[0] != colors[1] && colors[1] != colors[2] && colors[0] != colors[2])
print("PASS independent detail/period buttons, disabled switch, 64-point layout and provider accents")
