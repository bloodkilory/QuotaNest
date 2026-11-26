import AppKit
useTestLanguage()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let fixture = CCSwitchConnection(id:"claude|fixture",providerID:"fixture",harness:"claude",name:"DeepSeek",origin:"https://api.deepseek.com",configurationRole:"路由配置",supportsBalance:true)
let payload = try DeepSeekBalance.decode(Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"18.60","granted_balance":"3.60","topped_up_balance":"15.00"}]}"#.utf8))
var reading = ConnectedAccountReading()
_ = reading.complete(.success(payload),generation:reading.begin()!)
var refreshed: String?, settings = false, refreshCount = 0
let actions = ConnectedAccountsActions(select:{ _ in },refresh:{ refreshed = $0; refreshCount += 1 },settings:{ settings = true })
let model = ConnectedAccountsPresentation(connections:[fixture],enabled:[fixture.id],readings:[fixture.id:reading],source:.api(fixture.id),currency:nil,sourceError:nil)
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
let root = ConnectedAccountsView.build(model,actions:actions)
for id in ["refresh-account","settings"] {
    let button = descendants(root).first { $0.identifier?.rawValue == id } as! NSButton
    button.performClick(nil)
}
assert(refreshed == fixture.id && settings)
print("PASS native account actions: refresh and settings")
let idleRefresh = descendants(root).first { $0.identifier?.rawValue == "refresh-account" } as! RefreshIconButton
assert(!idleRefresh.isSpinning && !idleRefresh.hasSpinAnimation, "idle refresh button must not spin")
var busy = model; busy.readings[fixture.id]?.refreshing = true
let busyView = ConnectedAccountsView.build(busy,actions:actions)
let busyRefresh = descendants(busyView).first { $0.identifier?.rawValue == "refresh-account" } as! RefreshIconButton
assert(!busyRefresh.isEnabled && busyRefresh.toolTip == L("正在刷新…"))
assert(busyRefresh.isSpinning, "refreshing button must enter spinning state")
if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
    assert(busyRefresh.hasSpinAnimation, "refreshing button must animate rotation when reduce motion is off")
}
busyRefresh.performClick(nil); assert(refreshCount == 1)
print("PASS native refresh disabled and spinning during in-flight query")
for dark in [false,true] {
    app.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
    let content = ConnectedAccountsView.build(model,actions:actions)
    content.layoutSubtreeIfNeeded()
    let height = content.fittingSize.height
    assert(height > 100 && height < 220,"successful API balance stays compact")
    content.frame = NSRect(x:0,y:0,width:240,height:height)
    let surface = GlassAppearance.wrap(content,size:content.frame.size)
    if let glassType = NSClassFromString("NSGlassEffectView") {
        assert(surface.isKind(of: glassType), "new macOS must use the native glass surface")
        assert(surface.value(forKey: "contentView") as? NSView === content, "native glass must retain the interactive content")
        if surface.responds(to: NSSelectorFromString("style")) {
            assert((surface.value(forKey: "style") as? Int) == 1, "native glass must use clear Liquid Glass style")
        }
        if surface.responds(to: NSSelectorFromString("tintColor")) {
            let tint = surface.value(forKey: "tintColor") as? NSColor
            assert(tint != nil, "native glass must configure 50% transparency tint")
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency, let tint {
                var resolved: NSColor?
                app.appearance?.performAsCurrentDrawingAppearance { resolved = tint.usingColorSpace(.deviceRGB) }
                assert(abs((resolved?.alphaComponent ?? 0) - 0.50) < 0.02, "glass tint alpha must match 50% transparency")
            }
        }
        if surface.responds(to: NSSelectorFromString("effectIsInteractive")) {
            assert((surface.value(forKey: "effectIsInteractive") as? Bool) == false, "popover glass must disable interactive bounce")
            let capsuleSurface = GlassAppearance.wrap(NSView(), size: NSSize(width: 64, height: 18), cornerRadius: 9, interactive: true)
            assert((capsuleSurface.value(forKey: "effectIsInteractive") as? Bool) == true, "capsule glass keeps interactive effect when requested")
        }
    } else {
        assert(surface is NSVisualEffectView && surface.subviews.contains(content), "older macOS keeps a native material behind the content")
    }
    let window = NSWindow(contentRect:surface.bounds,styleMask:[.borderless],backing:.buffered,defer:false)
    window.appearance = app.appearance; window.contentView = surface
    window.layoutIfNeeded(); surface.layoutSubtreeIfNeeded()
    assert(content.frame.width == 240)
    surface.effectiveAppearance.performAsCurrentDrawingAppearance {
        if let bitmap = surface.bitmapImageRepForCachingDisplay(in:surface.bounds) {
            surface.cacheDisplay(in:surface.bounds,to:bitmap)
            let card = descendants(surface).first { $0 is NSBox }!
            assert(card.window === window && card.isDescendant(of: content), "card must remain attached inside the wrapped content")
            // 卡片颜色从实际卡片采样；系统材质的后台缓存只保留为诊断图。
            let cardBitmap = card.bitmapImageRepForCachingDisplay(in: card.bounds)!
            card.cacheDisplay(in: card.bounds, to: cardBitmap)
            let point = NSPoint(x: card.bounds.maxX - 8, y: card.bounds.midY)
            let scale = CGFloat(cardBitmap.pixelsWide) / card.bounds.width
            let color = cardBitmap.colorAt(x:Int(point.x * scale),y:Int((card.bounds.height - point.y) * scale))!.usingColorSpace(.deviceRGB)!
            assert(dark ? color.redComponent < 0.45 : color.redComponent > 0.75,"card contrast: dark=\(dark), color=\(color)")
            try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:".build/connected-native-" + (dark ? "dark" : "light") + ".png"))
        } else { fatalError("native snapshot unavailable") }
    }
    let replacement = NSView()
    assert(GlassAppearance.replaceContent(in: surface, with: replacement, size: content.frame.size), "glass wrapper must support in-place content replacement")
    if NSClassFromString("NSGlassEffectView") != nil {
        assert(surface.value(forKey: "contentView") as? NSView === replacement, "native glass must display replaced content")
    } else {
        assert(surface.subviews == [replacement], "fallback visual effect must replace old content subviews")
    }
}
print("PASS native account layout: 240-point surface, light/dark snapshots with synthetic balances")
