import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
func nativeSnapshot(_ content: NSView, name: String, dark: Bool) {
    let previousAppearance = app.appearance
    app.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
    defer { app.appearance = previousAppearance }
    let anchor = NSView(frame:NSRect(x:0,y:0,width:30,height:22))
    let host = NSWindow(contentRect:NSRect(x:400,y:500,width:30,height:22),styleMask:.borderless,backing:.buffered,defer:false)
    host.contentView = anchor; host.orderFront(nil)
    defer { host.orderOut(nil) }
    let scroll = NSScrollView(frame:content.bounds); scroll.drawsBackground = false; scroll.documentView = content
    let controller = NSViewController(); controller.view = GlassAppearance.wrap(scroll,size:scroll.frame.size)
    let popover = GlassPopover(); popover.contentViewController = controller; popover.contentSize = scroll.frame.size
    assert(!popover.isOpaque && popover.backgroundColor.alphaComponent == 0, "native glass must not be covered by an opaque popup background")
    popover.show(below: anchor)
    defer { popover.performClose(nil) }
    RunLoop.current.run(until:Date(timeIntervalSinceNow:0.05))
    let surface = controller.view.window!.contentView!.superview!
    controller.view.window!.layoutIfNeeded(); surface.layoutSubtreeIfNeeded()
    surface.effectiveAppearance.performAsCurrentDrawingAppearance {
        let bitmap = surface.bitmapImageRepForCachingDisplay(in:surface.bounds)!
        surface.cacheDisplay(in:surface.bounds,to:bitmap)
        try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:".build/compact-native-" + name + ".png"))
    }
}
let domain = "local.quotanest.source-ui." + UUID().uuidString
let defaults = UserDefaults(suiteName:domain)!
defer { defaults.removePersistentDomain(forName:domain) }
let selection = DisplaySelection(defaults:defaults)
let fixture = CCSwitchConnection(id:"claude|fixture",providerID:"fixture",harness:"claude",name:"账户 · 路由配置 · My production connection with a long name",origin:"https://api.deepseek.com",configurationRole:"路由配置",supportsBalance:true)
let other = CCSwitchConnection(id:"codex|other",providerID:"other",harness:"codex",name:"Other",origin:"https://other.example",configurationRole:"默认配置",supportsBalance:false)
let payload = try DeepSeekBalance.decode(Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"18.60","granted_balance":"3.60","topped_up_balance":"15.00"},{"currency":"USD","total_balance":"2.01","granted_balance":"0.01","topped_up_balance":"2.00"}]}"#.utf8))
var reading = ConnectedAccountReading()
_ = reading.complete(.success(payload),generation:reading.begin()!)
_ = reading.complete(.failure(DeepSeekQueryError(message:"DeepSeek 凭据失效；请在 CC Switch 检查")),generation:reading.begin()!)
let officialWindow = QuotaWindow(usedPercent:24,windowDurationMins:300,resetsAt:Date().timeIntervalSince1970 + 900)
let officialBucket = QuotaBucket(limitId:"codex",limitName:"Codex",planType:"fixture",primary:officialWindow,secondary:nil,credits:Credits(balance:"5.50",unlimited:false))
var officialReading = ProviderReading(snapshot:QuotaSnapshot(rateLimits:officialBucket,rateLimitsByLimitId:nil))
officialReading.lastSuccess = Date()
for language in [InterfaceLanguage.chinese,.english] {
    selection.select(.official(.codex))
    useTestLanguage(language)
    var settingsOpened = false, refreshes = 0
    var refreshedSources: [String?] = []
    var connections = [fixture,other]
    let actions = ConnectedAccountsActions(select:{ selection.select($0) },refresh:{ refreshedSources.append($0); refreshes += 1 },settings:{ settingsOpened = true })
    func view() -> NSStackView {
        let model = ConnectedAccountsPresentation(connections:connections,enabled:Set(connections.map(\.id)),readings:[fixture.id:reading],source:selection.source,currency:"CNY",sourceError:nil)
        return ConnectedAccountsView.build(model,officialDetails:OfficialQuotaView.build(provider:selection.provider,reading:officialReading,displayedPeriod:.short,authorize:{}),actions:actions)
    }
    func picker(_ view: NSView) -> DisplaySourcePicker { descendants(view).compactMap { $0 as? DisplaySourcePicker }.first! }
    let first = view()
    let expectedSettings = language == .english ? "Settings" : "设置"
    let settingsButton = descendants(first).first { $0.identifier?.rawValue == "settings" } as! NSButton
    assert(settingsButton.title.isEmpty && settingsButton.image != nil,"settings is an icon-only action")
    assert(settingsButton.toolTip == expectedSettings && settingsButton.accessibilityLabel() == expectedSettings,"settings keeps a localized tooltip and accessible name")
    let refreshButtons = descendants(first).compactMap { $0 as? NSButton }.filter { $0.identifier?.rawValue == "refresh-official" }
    assert(refreshButtons.count == 1 && refreshButtons[0].title.isEmpty && refreshButtons[0].image != nil,"official refresh is one icon-only header action")
    assert(refreshButtons[0].toolTip == (language == .english ? "Refresh now" : "立即刷新"))
    assert(refreshButtons[0].accessibilityLabel() == refreshButtons[0].toolTip)
    let busyOfficial = ConnectedAccountsView.build(ConnectedAccountsPresentation(connections:[],enabled:[],readings:[:],source:.official(.codex),currency:nil,sourceError:nil),officialRefreshing:true,actions:actions)
    let busyRefresh = descendants(busyOfficial).first { $0.identifier?.rawValue == "refresh-official" } as! NSButton
    assert(!busyRefresh.isEnabled && busyRefresh.toolTip == L("正在刷新…"))
    busyRefresh.performClick(nil); assert(refreshes == 0,"in-flight official refresh cannot repeat")
    assert(picker(first).accessibilityLabel() == (language == .english ? "Menu bar shows" : "菜单栏显示"))
    assert(first.arrangedSubviews.firstIndex(of:picker(first)) == 1)
    assert(descendants(first).filter { $0 is NSPopUpButton }.count == 1)
    assert(picker(first).numberOfItems == QuotaProviderID.allCases.count + 2,"official sources, Harness and supported connected API sources")
    assert(picker(first).itemTitles.last!.hasSuffix(fixture.name),"user names must not be translated")
    assert(!descendants(first).contains { $0.identifier?.rawValue == "pin-account" })
    func choose(_ index: Int) {
        let control = picker(view()); control.selectItem(at:index)
        control.sendAction(control.action,to:control.target)
    }
    choose(0); assert(selection.source == .official(.codex) && selection.accountID == nil)
    choose(QuotaProviderID.allCases.count + 1); assert(selection.source == .api(fixture.id) && selection.accountID == fixture.id)
    let api = view()
    let removed = ConnectedAccountsView.build(ConnectedAccountsPresentation(connections:[],enabled:[],readings:[fixture.id:reading],source:.api(fixture.id),currency:nil,sourceError:nil),actions:actions)
    assert(!(descendants(removed).first { $0.identifier?.rawValue == "refresh-account" } as! NSButton).isEnabled)
    var inFlight = reading; inFlight.refreshing = true
    let busyAPI = ConnectedAccountsView.build(ConnectedAccountsPresentation(connections:[fixture],enabled:[fixture.id],readings:[fixture.id:inFlight],source:.api(fixture.id),currency:nil,sourceError:nil),actions:actions)
    let busyAPIRefresh = descendants(busyAPI).first { $0.identifier?.rawValue == "refresh-account" } as! NSButton
    assert(!busyAPIRefresh.isEnabled && busyAPIRefresh.toolTip == L("正在刷新…") && busyAPIRefresh.accessibilityLabel() == L("正在刷新…"))
    busyAPIRefresh.performClick(nil); assert(refreshes == 0)
    let strings = descendants(api).compactMap { ($0 as? NSTextField)?.stringValue }
    assert(picker(api).toolTip!.contains(fixture.name) && strings.contains("CNY 18.60"))
    assert(strings.contains(L("DeepSeek 凭据失效；请在 CC Switch 检查")))
    let refresh = descendants(api).first { $0.identifier?.rawValue == "refresh-account" } as! NSButton
    refresh.performClick(nil); assert(refreshes == 1 && refreshedSources.last! == fixture.id)
    (descendants(api).first { $0.identifier?.rawValue == "settings" } as! NSButton).performClick(nil)
    assert(settingsOpened && selection.source == .api(fixture.id))
    connections.append(CCSwitchConnection(id:"codex|new",providerID:"new",harness:"codex",name:"New",origin:fixture.origin,configurationRole:"默认配置",supportsBalance:true))
    assert(picker(view()).numberOfItems == QuotaProviderID.allCases.count + 3 && selection.source == .api(fixture.id))
    connections = []
    let missing = view()
    assert(!descendants(missing).compactMap { ($0 as? NSTextField)?.stringValue }.contains("CNY 18.60"))
    choose(1); assert(selection.source == .official(.claude) && selection.accountID == nil)
    assert(defaults.string(forKey:"pinnedCCSwitchConnection") == nil)
    assert(DisplaySelection(defaults:defaults).source == .official(.claude))
    selection.select(.harness)
    let harnessBalance = HarnessBalance(normal:[DeepSeekWallet(currency:"CNY",total:12.34,granted:0,toppedUp:0)],bonus:[DeepSeekWallet(currency:"CNY",total:3.21,granted:0,toppedUp:0)])
    let harnessReading = HarnessReading(balance:harnessBalance,lastSuccess:Date(),failure:nil,refreshing:false)
    let harnessModel = ConnectedAccountsPresentation(connections:connections,enabled:Set(connections.map(\.id)),readings:[:],source:.harness,currency:"CNY",sourceError:nil,harnessReading:harnessReading)
    let harnessView = ConnectedAccountsView.build(harnessModel,actions:actions)
    let harnessLabels = descendants(harnessView).compactMap { ($0 as? NSTextField)?.stringValue }
    assert(harnessLabels.contains("CNY 12.34") && harnessLabels.contains(L("赠送余额    ") + "CNY 3.21"),"Harness keeps recharge and bonus amounts separate")
    assert(!harnessLabels.contains("CNY 15.55"),"Harness does not invent a combined wallet")
    let harnessRefresh = descendants(harnessView).first { $0.identifier?.rawValue == "refresh-harness" } as! NSButton
    harnessRefresh.performClick(nil)
    assert(refreshedSources.last! == nil,"Harness refresh must not target a CC Switch connection")
    assert(picker(harnessView).titleOfSelectedItem == "DeepSeek Harness · " + L("充值余额"))
    // Real AppKit layout, including long English error text and untouched long user names.
    connections = [fixture]; selection.select(.api(fixture.id))
    for source in [DisplaySource.api(fixture.id),.official(.codex),.official(.zcode),.harness] {
    selection.select(source)
    let content = view(); content.layoutSubtreeIfNeeded()
    let height = content.fittingSize.height
    content.frame = NSRect(x:0,y:0,width:240,height:height)
    let surface = GlassAppearance.wrap(content,size:content.frame.size)
    let window = NSWindow(contentRect:surface.bounds,styleMask:.borderless,backing:.buffered,defer:false)
    window.appearance = NSAppearance(named:.aqua); window.contentView = surface
    window.layoutIfNeeded(); surface.layoutSubtreeIfNeeded()
    for child in descendants(content) where child is NSControl {
        let bounds = child.convert(child.bounds,to:content)
        assert(bounds.minX >= -1 && bounds.maxX <= 241,"controls must fit the compact 240-point popover")
    }
    assert(picker(content).convert(picker(content).bounds,to:content).maxY > height - 130)
    let gear = descendants(content).first { $0.identifier?.rawValue == "settings" }!
    let title = descendants(content).compactMap { $0 as? NSTextField }.first { $0.stringValue == L("余度 QuotaNest") }!
    let refreshID = selection.source == .harness ? "refresh-harness" : selection.accountID == nil ? "refresh-official" : "refresh-account"
    let refreshIcon = descendants(content).first { $0.identifier?.rawValue == refreshID } as! NSButton
    assert(refreshIcon.title.isEmpty && refreshIcon.image != nil && refreshIcon.toolTip == L("立即刷新"))
    func checkHeaderLayout(_ phase: String) {
        // Auto Layout aligns these rectangles; SF Symbols have different optical frame insets.
        func alignmentBounds(_ view: NSView) -> NSRect {
            view.superview!.convert(view.alignmentRect(forFrame:view.frame),to:content)
        }
        let gearBounds = alignmentBounds(gear), titleBounds = alignmentBounds(title), refreshBounds = alignmentBounds(refreshIcon)
        let header = content.arrangedSubviews.first!
        let context = "phase=\(phase) language=\(language.rawValue) source=\(source) windowVisible=\(window.isVisible) content=\(content.frame) header=\(header.frame) refreshFrame=\(refreshIcon.convert(refreshIcon.bounds,to:content)) gearFrame=\(gear.convert(gear.bounds,to:content)) refreshAlignment=\(refreshBounds) gearAlignment=\(gearBounds) refreshInsets=\(refreshIcon.alignmentRectInsets) gearInsets=\(gear.alignmentRectInsets) headerNeedsLayout=\(header.needsLayout) ambiguous=\(header.hasAmbiguousLayout)"
        assert(gearBounds.minX > titleBounds.maxX && abs(gearBounds.midY - titleBounds.midY) < 1,"settings sits to the right of the title on the same row; " + context)
        assert(gearBounds.maxX > 210 && gearBounds.maxY > height - 35,"settings stays in the top-right corner; " + context)
        assert(refreshBounds.maxX < gearBounds.minX && abs(refreshBounds.midY - gearBounds.midY) < 1,"refresh sits immediately left of settings in the title row; " + context)
        for bounds in [refreshBounds,gearBounds] {
            assert(abs(bounds.width - 22) < 0.01 && abs(bounds.height - 22) < 0.01,"header icons keep 22-point alignment bounds; " + context)
        }
        assert(abs(gearBounds.minX - refreshBounds.maxX - 6) < 0.01,"header icons keep a 6-point gap; " + context)
    }
    checkHeaderLayout("initial-offscreen")
    window.orderFront(nil); window.displayIfNeeded()
    _ = RunLoop.current.run(mode:.default,before:Date(timeIntervalSinceNow:0.01))
    window.layoutIfNeeded(); surface.layoutSubtreeIfNeeded()
    assert(window.isVisible,"native header layout must also be checked in a visible window")
    checkHeaderLayout("first-visible")
    window.orderOut(nil)
    assert(descendants(content).compactMap { $0 as? NSButton }.allSatisfy { $0.title != L("立即刷新") },"no bottom text refresh button remains")
    if case .official = source {
        let labels = descendants(content).compactMap { ($0 as? NSTextField)?.stringValue }
        assert(labels.contains(L("%@    剩余 %@",L("%@ 小时额度","5"),"76.0%")))
        assert(labels.contains(L("Credits 余额：%@","5.50")))
        if source == .official(.codex) { assert(descendants(content).contains { $0.toolTip?.contains("fixture") == true },"the plan/source metadata remains available as a tooltip") }
        let before = refreshes
        refreshIcon.performClick(nil); assert(refreshes == before + 1 && refreshedSources.last! == nil)
        if source == .official(.codex) { assert(height >= 110 && height <= 160,"ordinary successful Codex details remain compact: \(language) height \(height)") }
    }
    surface.effectiveAppearance.performAsCurrentDrawingAppearance {
        let bitmap = surface.bitmapImageRepForCachingDisplay(in:surface.bounds)!
        surface.cacheDisplay(in:surface.bounds,to:bitmap)
        try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:".build/bilingual-" + language.rawValue + "-" + (selection.accountID == nil ? selection.provider.rawValue : "api") + ".png"))
    }
    nativeSnapshot(content,name:language.rawValue + "-" + (selection.accountID == nil ? selection.provider.rawValue : "api"),dark:language == .chinese)
    }
}
print("PASS bilingual native source picker, Codex→API→Claude, settings/new-source stability, removed-source recovery and 240-point rendering")
for language in [InterfaceLanguage.chinese,.english] {
    selection.select(.official(.codex))
    useTestLanguage(language)
    let original = selection.source
    var wentBack = false, connected = false, checked = false, installed = false, login: Bool?, quit = false
    let actions = SettingsActions(back:{ wentBack = true },language:{ Localization.shared.preference = $0 },connect:{ connected = true },checkUpdate:{ checked = true },installUpdate:{ installed = true },login:{ login = $0 },quit:{ quit = true })
    let model = SettingsPresentation(connections:[fixture,other],enabled:[fixture.id,other.id],sourceError:nil,discovering:false,language:language,version:"1.8.0",updateState:.available("1.9.0"),previousStatus:UpdateInstallStatus(state:"installed",message:"已更新到 v%@",arguments:["1.8.0"]),availableVersion:"1.9.0",canInstall:true,loginEnabled:false)
    let content = SettingsView.build(model,actions:actions)
    assert(content.fittingSize.width == 380,"settings retains its readable form width")
    let buttons = descendants(content).compactMap { $0 as? NSButton }
    for id in ["back-details","connect-source","check-updates","install-update","launch-at-login","quit"] { buttons.first { $0.identifier?.rawValue == id }!.performClick(nil) }
    assert(wentBack && connected && checked && installed && login == true && quit)
    assert(selection.source == original,"settings actions never mutate the displayed source")
    let expected = language == .english ? ["Back to details","Connect existing tools…","Check for updates","Update to v1.9.0","Launch at login","Quit QuotaNest"] : ["返回详情","连接已有工具…","检查更新","更新到 v1.9.0","登录时启动","退出余度 QuotaNest"]
    for title in expected { assert(buttons.contains { $0.title == title }) }
    let fields = descendants(content).compactMap { ($0 as? NSTextField)?.stringValue }
    assert(fields.contains(fixture.name + " · Claude Code"))
    assert(fields.contains(language == .english ? "Routed configuration · https://api.deepseek.com" : "路由配置 · https://api.deepseek.com"))
    content.layoutSubtreeIfNeeded()
    content.frame = NSRect(x:0,y:0,width:380,height:content.fittingSize.height)
    let surface = GlassAppearance.wrap(content,size:content.frame.size)
    let window = NSWindow(contentRect:surface.bounds,styleMask:.borderless,backing:.buffered,defer:false)
    window.appearance = NSAppearance(named:.aqua); window.contentView = surface
    window.layoutIfNeeded(); surface.layoutSubtreeIfNeeded()
    for child in descendants(content) where child is NSControl {
        let bounds = child.convert(child.bounds,to:content)
        assert(bounds.minX >= -1 && bounds.maxX <= 381)
    }
    surface.effectiveAppearance.performAsCurrentDrawingAppearance {
        let bitmap = surface.bitmapImageRepForCachingDisplay(in:surface.bounds)!
        surface.cacheDisplay(in:surface.bounds,to:bitmap)
        try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:".build/bilingual-" + language.rawValue + "-settings.png"))
    }
    let languagePicker = descendants(content).compactMap { $0 as? LanguagePicker }.first!
    assert(languagePicker.itemTitles == [language == .english ? "Follow system" : "跟随系统","中文","English"])
    languagePicker.selectItem(at:language == .english ? 1 : 2)
    languagePicker.sendAction(languagePicker.action,to:languagePicker.target)
    assert(Localization.shared.preference == (language == .english ? .chinese : .english))
    assert(selection.source == original)
}
print("PASS bilingual native settings, language change, connection/update/login/quit actions, provenance and 380-point layout")
let sameName = CCSwitchConnection(id:"claude|same-name",providerID:"same-name",harness:fixture.harness,name:fixture.name,origin:fixture.origin,configurationRole:"默认配置",supportsBalance:true)
let duplicates = ConnectedAccountsPresentation(connections:[fixture,sameName],enabled:[fixture.id,sameName.id],readings:[:],source:.api(sameName.id),currency:nil,sourceError:nil)
var pickedDuplicate: DisplaySource?
let duplicateView = ConnectedAccountsView.build(duplicates,actions:ConnectedAccountsActions(select:{ pickedDuplicate = $0 },refresh:{ _ in },settings:{}))
let duplicatePicker = descendants(duplicateView).compactMap { $0 as? DisplaySourcePicker }.first!
assert(duplicatePicker.numberOfItems == QuotaProviderID.allCases.count + 3,"same-named connections must retain separate source items")
duplicatePicker.selectItem(at:QuotaProviderID.allCases.count + 2); duplicatePicker.sendAction(duplicatePicker.action,to:duplicatePicker.target)
assert(pickedDuplicate == .api(sameName.id))
print("PASS duplicate user connection names retain independent source identities")
let namelessGroups = try QuotaSnapshot.decode(Data(#"{"rateLimitsByLimitId":{"group-alpha":{"primary":{"usedPercent":10,"windowDurationMins":300}},"group-beta":{"primary":{"usedPercent":20,"windowDurationMins":10080}}}}"#.utf8))
for language in [InterfaceLanguage.english,.chinese] {
    useTestLanguage(language)
    let details = OfficialQuotaView.build(provider:.codex,reading:ProviderReading(snapshot:namelessGroups),displayedPeriod:.short,authorize:{})
    let headings = descendants(details).compactMap { $0 as? NSButton }.map(\.title).filter { $0 != L("自动（默认）") }
    assert(headings == ["group-alpha","group-beta"],"nameless official quota groups retain distinct original map-key headings in each language")
}
print("PASS nameless official quota groups retain original distinct headings in English and Chinese")

for language in [InterfaceLanguage.chinese,.english] {
    selection.select(.official(.codex))
    useTestLanguage(language)
    for provider in QuotaProviderID.allCases {
        var failed = officialReading; failed.error = L("DeepSeek 凭据失效；请在 CC Switch 检查")
        let details = OfficialQuotaView.build(provider:provider,reading:failed,displayedPeriod:.short,authorize:{})
        let model = ConnectedAccountsPresentation(connections:[],enabled:[],readings:[:],source:.official(provider),currency:nil,sourceError:nil)
        let root = ConnectedAccountsView.build(model,officialDetails:details,actions:ConnectedAccountsActions(select:{ _ in },refresh:{ _ in },settings:{}))
        root.layoutSubtreeIfNeeded(); root.frame = NSRect(x:0,y:0,width:240,height:root.fittingSize.height)
        let labels = descendants(root).compactMap { ($0 as? NSTextField)?.stringValue }
        assert(labels.contains { $0.contains(failed.error!) && $0.contains(L("\n当前百分比为上次成功查询结果。")) },"failed official refresh keeps the complete error and stale warning")
        for control in descendants(root) where control is NSControl {
            let bounds = control.convert(control.bounds,to:root)
            assert(bounds.minX >= -1 && bounds.maxX <= 241,"every official provider error/action fits the compact width")
        }
    }
    let details = OfficialQuotaView.build(provider:.codex,reading:ProviderReading(snapshot:namelessGroups),displayedPeriod:.short,authorize:{})
    let labels = descendants(details).compactMap { ($0 as? NSTextField)?.stringValue }
    assert(labels.contains(L("%@    剩余 %@",L("%@ 小时额度","5"),"90.0%")))
    assert(labels.contains(L("%@    剩余 %@",L("%@ 天额度","7"),"80.0%")))
    assert(labels.filter { $0 == L("重置时间：未提供") }.count == 2,"each quota group keeps its own reset status")
}
print("PASS all eight official provider errors/actions fit 240 points; multiple quota groups and reset states remain visible in both languages")

let multiWindow = try QuotaSnapshot.decode(Data(#"{"rateLimitsByLimitId":{"group-a":{"limitName":"Alpha","primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":1},"secondary":{"usedPercent":30,"windowDurationMins":10080},"credits":{"balance":"7.25","unlimited":false}},"group-b":{"limitName":"Beta","primary":{"usedPercent":20,"windowDurationMins":1440}}}}"#.utf8))
for language in [InterfaceLanguage.chinese,.english] {
    selection.select(.official(.codex))
    useTestLanguage(language)
    let details = OfficialQuotaView.build(provider:.codex,reading:ProviderReading(snapshot:multiWindow),displayedPeriod:.weekly,authorize:{})
    let labels = descendants(details).compactMap { ($0 as? NSTextField)?.stringValue }
    let visibleText = labels + descendants(details).compactMap { ($0 as? NSButton)?.title }
    for value in ["Alpha","Beta",L("Credits 余额：%@","7.25"),L("%@    剩余 %@",L("%@ 小时额度","5"),"90.0%"),L("%@    剩余 %@",L("%@ 天额度","7"),"70.0%"),L("%@    剩余 %@",L("%@ 天额度","1"),"80.0%")] { assert(visibleText.contains(value)) }
    assert(descendants(details).filter { $0 is NSProgressIndicator }.count == 3,"all windows remain visible, beyond the selected capsule period")
    let formatter = DateFormatter(); formatter.dateFormat = "MM-dd HH:mm"
    assert(labels.contains(L("重置：%@ · 等待服务更新",formatter.string(from:Date(timeIntervalSince1970:1)))))
}
print("PASS compact details retain multiple windows, credits and elapsed-reset status in both languages")

for language in [InterfaceLanguage.chinese,.english] {
    selection.select(.official(.codex))
    useTestLanguage(language)
    let expiry = Date().timeIntervalSince1970 + 3600
    let window = QuotaWindow(usedPercent:25,windowDurationMins:nil,resetsAt:nil,periodLabel:"一次性额度",localizesPeriodLabel:true,expiresAt:expiry)
    let bucket = QuotaBucket(limitId:"synthetic-start",limitName:"Start Plan · Synthetic Model",planType:"Start Plan",primary:window,secondary:nil,credits:nil)
    let details = OfficialQuotaView.build(provider:.zcode,reading:ProviderReading(snapshot:QuotaSnapshot(rateLimits:bucket,rateLimitsByLimitId:nil)),displayedPeriod:.billing,authorize:{})
    let labels = descendants(details).compactMap { ($0 as? NSTextField)?.stringValue }
    let formatter = DateFormatter(); formatter.dateFormat = "MM-dd HH:mm"
    assert(labels.contains(L("到期：%@",formatter.string(from:Date(timeIntervalSince1970:expiry)))))
    assert(!labels.contains(L("重置时间：未提供")),"one-time Start Plan expires rather than resetting")
    assert(labels.contains(L("%@    剩余 %@",language == .english ? "One-time quota" : "一次性额度","75.0%")))
}
print("PASS Start Plan one-time expiry and quota label render in Chinese and English without a reset claim")


let modelSnapshot = QuotaSnapshot(rateLimits:nil,rateLimitsByLimitId:[
    "zcode-start-0":QuotaBucket(limitId:"zcode-start-0",limitName:"Start Plan · Main",planType:"Start Plan",primary:QuotaWindow(usedPercent:100,windowDurationMins:1440,resetsAt:2000),secondary:nil,credits:nil),
    "zcode-start-1":QuotaBucket(limitId:"zcode-start-1",limitName:"Start Plan · Flash",planType:"Start Plan",primary:QuotaWindow(usedPercent:0,windowDurationMins:1440,resetsAt:3000),secondary:nil,credits:nil)
])
let modelDetails = OfficialQuotaView.build(provider:.zcode,reading:ProviderReading(snapshot:modelSnapshot),displayedPeriod:.daily,authorize:{})
assert(descendants(modelDetails).compactMap { $0 as? NSButton }.contains { $0.title == "Start Plan · Flash" },"multiple model quotas need native radio controls to choose the capsule reading")

for language in [InterfaceLanguage.chinese,.english] {
    selection.select(.official(.codex))
    useTestLanguage(language)
    selection.selectModel(nil,for:.zcode)
    var modelReading = ProviderReading(snapshot:modelSnapshot)
    func selectedDetails() -> NSStackView {
        modelReading.modelID = selection.model(for:.zcode)
        return OfficialQuotaView.build(provider:.zcode,reading:modelReading,displayedPeriod:modelReading.period(for:.zcode,preferred:.short),selectModel:{ selection.selectModel($0,for:.zcode) },authorize:{})
    }
    let automatic = selectedDetails()
    let radios = descendants(automatic).compactMap { $0 as? NSButton }
    assert(radios.count == 3 && radios.filter { $0.state == .on }.count == 1)
    assert(radios[0].title == L("自动（默认）") && radios[0].state == .on)
    let flash = radios.first { $0.title == "Start Plan · Flash" }!
    flash.performClick(nil)
    assert(selection.model(for:.zcode) == "name:Start Plan · Flash")
    assert(DisplaySelection(defaults:defaults).model(for:.zcode) == selection.model(for:.zcode),"model preference survives recreation")
    assert(selection.model(for:.claude) == nil,"model preference is independent per harness")
    let selected = selectedDetails()
    assert(modelReading.window(for:.zcode,period:.daily)?.remaining == 100 && modelReading.window(for:.zcode,period:.daily)?.resetsAt == 3000)
    assert(descendants(selected).compactMap { $0 as? NSButton }.filter { $0.state == .on }.map { $0.title } == ["Start Plan · Flash"],"exactly the displayed model radio is checked")
    assert(selected.toolTip!.contains("Start Plan · Flash"))
    let model = ConnectedAccountsPresentation(connections:[],enabled:[],readings:[:],source:.official(.zcode),currency:nil,sourceError:nil)
    let content = ConnectedAccountsView.build(model,officialDetails:selected,actions:ConnectedAccountsActions(select:{ _ in },refresh:{ _ in },settings:{}))
    content.layoutSubtreeIfNeeded(); content.frame = NSRect(x:0,y:0,width:240,height:content.fittingSize.height)
    nativeSnapshot(content,name:language.rawValue + "-model-selection",dark:true)
    for control in descendants(content).compactMap({ $0 as? NSButton }) {
        let bounds = control.convert(control.bounds,to:content)
        assert(bounds.minX >= -1 && bounds.maxX <= 241,"model radios fit compact popover")
    }
    (descendants(selected).compactMap { $0 as? NSButton }.first { $0.title == L("自动（默认）") }!).performClick(nil)
    assert(selection.model(for:.zcode) == nil,"automatic clears only this harness model preference")
}
print("PASS bilingual native model radio, persistence, exact quota/reset and compact layout")

var singleSelected = ProviderReading(snapshot:QuotaSnapshot(rateLimits:officialBucket,rateLimitsByLimitId:nil))
singleSelected.modelID = singleSelected.models[0].id
let singleDetails = OfficialQuotaView.build(provider:.codex,reading:singleSelected,displayedPeriod:.short,authorize:{})
let singleRadios = descendants(singleDetails).compactMap { $0 as? NSButton }
assert(singleRadios.count == 2 && singleRadios.contains { $0.title == L("自动（默认）") },"one remaining selected group can still return to automatic")
assert(singleRadios.allSatisfy { $0.identifier != nil } && Set(singleRadios.compactMap { $0.identifier?.rawValue }).count == 2,"radio identities preserve keyboard focus across popover rebuilds")
var removedSelection = ProviderReading(snapshot:modelSnapshot); removedSelection.modelID = "name:Removed Model"
let fallbackDetails = OfficialQuotaView.build(provider:.zcode,reading:removedSelection,displayedPeriod:.daily,authorize:{})
assert(descendants(fallbackDetails).compactMap { $0 as? NSButton }.filter { $0.state == .on }.map { $0.title } == [L("自动（默认）")],"temporarily removed model clearly checks actual Automatic choice")
for language in [InterfaceLanguage.chinese,.english] {
    selection.select(.official(.codex))
    useTestLanguage(language)
    var snapshot=QuotaSnapshot(rateLimits:officialBucket,rateLimitsByLimitId:nil)
    snapshot.loginSource="Claude Code 同账号备用"
    let reading=ProviderReading(snapshot:snapshot)
    let view=OfficialQuotaView.build(provider:.claude,reading:reading,displayedPeriod:.short,authorize:{})
    let text=descendants(view).compactMap { ($0 as? NSTextField)?.stringValue }
    assert(text.contains(L("登录来源：%@",L("Claude Code 同账号备用"))),"active Claude login source is translated")
    assert(view.fittingSize.width<=220.1,"desktop source label stays inside compact details")
}
print("PASS compact bilingual Claude login source label")

// 设置与详情切换时，透明面板始终贴近同一菜单栏锚点并保持焦点。
let popupAnchor = NSView(frame: NSRect(x: 0, y: 0, width: 64, height: 22))
let popupHost = NSWindow(contentRect: NSRect(x: 1400, y: 949, width: 64, height: 22), styleMask: .borderless, backing: .buffered, defer: false)
popupHost.contentView = popupAnchor
let resizingPopup = GlassPopover()
let popupController = NSViewController()
popupController.view = GlassAppearance.wrap(NSView(), size: NSSize(width: 240, height: 100))
resizingPopup.contentViewController = popupController
resizingPopup.contentSize = NSSize(width: 240, height: 100)
resizingPopup.show(below: popupAnchor)
let originalFrame = resizingPopup.frame
let originalKeyState = resizingPopup.isKeyWindow
resizingPopup.contentSize = NSSize(width: 380, height: 100)
assert(abs(resizingPopup.frame.maxY - originalFrame.maxY) < 0.01)
assert(resizingPopup.isKeyWindow == originalKeyState, "resizing must not steal keyboard focus")
if let visible = (popupHost.screen ?? NSScreen.main)?.visibleFrame {
    assert(resizingPopup.frame.maxX <= visible.maxX - 8.0 + 0.01)
} else {
    assert(abs(resizingPopup.frame.midX - originalFrame.midX) < 0.01)
}
resizingPopup.contentSize = NSSize(width: 240, height: 100)
assert(resizingPopup.frame == originalFrame)
resizingPopup.cancelOperation(nil)
assert(!resizingPopup.isShown, "Escape must close the popup")
resizingPopup.show(below: popupAnchor)
resizingPopup.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: resizingPopup))
assert(!resizingPopup.isShown, "losing keyboard focus must close the popup")
print("PASS glass popup anchoring at 240/380/240 points, focus preservation and dismiss actions")
