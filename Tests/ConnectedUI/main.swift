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
var busy = model; busy.readings[fixture.id]?.refreshing = true
let busyView = ConnectedAccountsView.build(busy,actions:actions)
let busyRefresh = descendants(busyView).first { $0.identifier?.rawValue == "refresh-account" } as! NSButton
assert(!busyRefresh.isEnabled && busyRefresh.toolTip == L("正在刷新…"))
busyRefresh.performClick(nil); assert(refreshCount == 1)
print("PASS native refresh disabled during in-flight query")
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
}
print("PASS native account layout: 240-point surface, light/dark snapshots with synthetic balances")
