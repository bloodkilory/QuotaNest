import AppKit

final class AccountActionButton: NSButton {
    private let handler: () -> Void
    init(_ title: String, id: String? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame:.zero)
        self.title = title; bezelStyle = .rounded; target = self; action = #selector(invoke)
        if let id { identifier = NSUserInterfaceItemIdentifier(id) }
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func invoke() { handler() }
}

struct ConnectedAccountsPresentation {
    var connections: [CCSwitchConnection]
    var enabled: Set<String>
    var readings: [String:ConnectedAccountReading]
    var source: DisplaySource
    var currency: String?
    var sourceError: String?
    var harnessReading = HarnessReading()
}

struct ConnectedAccountsActions {
    let select: (DisplaySource) -> Void
    let refresh: (String?) -> Void
    let settings: () -> Void
}

final class DisplaySourcePicker: NSPopUpButton {
    private let sources: [DisplaySource]
    private let changed: (DisplaySource) -> Void
    init(sources: [DisplaySource], titles: [String], selected: DisplaySource, changed: @escaping (DisplaySource) -> Void) {
        self.sources = sources; self.changed = changed
        super.init(frame:.zero,pullsDown:false)
        menu = NSMenu()
        for title in titles { menu?.addItem(NSMenuItem(title:title,action:nil,keyEquivalent:"")) }
        selectItem(at:sources.firstIndex(of:selected) ?? 0)
        target = self; action = #selector(selectedSource)
        identifier = NSUserInterfaceItemIdentifier("display-source")
        widthAnchor.constraint(equalToConstant:220).isActive = true
        controlSize = .small; font = .systemFont(ofSize:11)
        setAccessibilityLabel(L("菜单栏显示")); toolTip = titleOfSelectedItem
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func selectedSource() { changed(sources[indexOfSelectedItem]) }
}

enum ConnectedAccountsView {
    static let width: CGFloat = 240
    static func text(_ value: String, size: CGFloat = 12, secondary: Bool = false, bold: Bool = false, width: CGFloat = 344) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString:value)
        field.font = .systemFont(ofSize:size,weight:bold ? .semibold : .regular)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.widthAnchor.constraint(equalToConstant:width).isActive = true
        field.setContentCompressionResistancePriority(.required,for:.vertical)
        return field
    }
    static func stack(width: CGFloat = 344, spacing: CGFloat = 9) -> NSStackView {
        let view = NSStackView(); view.orientation = .vertical; view.alignment = .leading; view.spacing = spacing
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant:width).isActive = true
        return view
    }
    static func build(_ model: ConnectedAccountsPresentation, officialDetails: NSView? = nil, officialRefreshing: Bool = false, actions: ConnectedAccountsActions) -> NSStackView {
        let root = stack(width:width,spacing:5)
        root.edgeInsets = NSEdgeInsets(top:8,left:10,bottom:8,right:10)
        let accounts = model.connections.filter { model.enabled.contains($0.id) && $0.supportsBalance }
        let refreshing: Bool, refreshID: String, accountID: String?, canRefresh: Bool
        switch model.source {
        case .official:
            refreshing = officialRefreshing; refreshID = "refresh-official"; accountID = nil; canRefresh = true
        case .harness:
            refreshing = model.harnessReading.refreshing; refreshID = "refresh-harness"; accountID = nil; canRefresh = true
        case .api(let id):
            refreshing = model.readings[id]?.refreshing ?? false; refreshID = "refresh-account"; accountID = id
            canRefresh = accounts.contains { $0.id == id }
        }
        let header = NSStackView(); header.orientation = .horizontal; header.alignment = .centerY; header.spacing = 6
        header.widthAnchor.constraint(equalToConstant:220).isActive = true
        header.addArrangedSubview(text(L("余度 QuotaNest"),size:12,bold:true,width:164))
        let refresh = icon("arrow.clockwise",label:L(refreshing ? "正在刷新…" : "立即刷新"),id:refreshID) { actions.refresh(accountID) }
        refresh.isEnabled = canRefresh && !refreshing
        header.addArrangedSubview(refresh)
        header.addArrangedSubview(icon("gearshape",label:L("设置"),id:"settings",handler:actions.settings))
        root.addArrangedSubview(header)
        var sources = QuotaProviderID.allCases.map { DisplaySource.official($0) } + [.harness] + accounts.map { .api($0.id) }
        var titles = QuotaProviderID.allCases.map { $0.title + " · " + L("套餐余量") }
        titles.append("DeepSeek Harness · " + L("充值余额"))
        titles += accounts.map { "DeepSeek · " + L("API 余额") + " · " + ($0.harness == "claude" ? "Claude Code" : "Codex") + " · " + $0.displayName }
        if !sources.contains(model.source) { sources.append(model.source); titles.append(L("API 余额 · 来源不可用")) }
        root.addArrangedSubview(DisplaySourcePicker(sources:sources,titles:titles,selected:model.source,changed:actions.select))
        switch model.source {
        case .official:
            if let officialDetails { root.addArrangedSubview(officialDetails) }
        case .harness:
            let reading = model.harnessReading
            let card = stack(width:204,spacing:3)
            card.toolTip = L("来自 DeepSeek Harness 官方登录；充值余额与赠送余额分开展示")
            let wallets = reading.balance?.normal ?? []
            let wallet = wallets.first { $0.currency == model.currency } ?? wallets.first
            card.addArrangedSubview(text(L("充值余额"),size:10,secondary:true,width:204))
            card.addArrangedSubview(text(wallet?.displayAmount ?? (reading.refreshing ? L("正在查询…") : "—"),size:20,bold:true,width:204))
            if reading.error != nil && reading.balance != nil { card.addArrangedSubview(text(L("上次成功余额 · 当前数据已过期"),size:10,secondary:true,width:204)) }
            for other in wallets where other.currency != wallet?.currency { card.addArrangedSubview(text(L("另一币种    ") + other.displayAmount,size:10,secondary:true,width:204)) }
            for bonus in reading.balance?.bonus ?? [] { card.addArrangedSubview(text(L("赠送余额    ") + bonus.displayAmount,size:10,width:204)) }
            if let error = reading.error { card.addArrangedSubview(text(error,size:10,secondary:true,width:204)) }
            if reading.balance == nil { card.addArrangedSubview(text(L("请先在 DeepSeek Harness 官方应用中登录。"),size:10,secondary:true,width:204)) }
            let formatter = DateFormatter(); formatter.locale = Localization.shared.locale; formatter.timeStyle = .medium
            let time = reading.lastSuccess.map { formatter.string(from:$0) } ?? L("尚未成功")
            card.addArrangedSubview(text(L("更新：") + time + L(" · 每 2 分钟检查"),size:10,secondary:true,width:204))
            card.layoutSubtreeIfNeeded()
            root.addArrangedSubview(GlassAppearance.card(card,width:220,height:card.fittingSize.height))
        case .api(let id):
            let connection = accounts.first { $0.id == id }
            let reading = connection == nil ? ConnectedAccountReading() : model.readings[id] ?? ConnectedAccountReading()
            let card = stack(width:204,spacing:3)
            card.toolTip = connection.map { $0.displayName + "\n" + L("来自 CC Switch · ") + ($0.harness == "claude" ? "Claude Code" : "Codex") }
            if connection == nil { card.addArrangedSubview(text(L("来源已移除或不再支持，请选择其他显示来源"),size:10,secondary:true,width:204)) }
            let wallets = reading.balance?.wallets ?? []
            let wallet = wallets.first { $0.currency == model.currency } ?? wallets.first
            if let wallet {
                card.addArrangedSubview(text(wallet.displayAmount,size:20,bold:true,width:204))
                if reading.error != nil { card.addArrangedSubview(text(L("上次成功余额 · 当前数据已过期"),size:10,secondary:true,width:204)) }
                card.addArrangedSubview(text(L("充值余额    ") + wallet.currency + " " + DeepSeekWallet.amount(wallet.toppedUp),size:10,width:204))
                card.addArrangedSubview(text(L("赠送余额    ") + wallet.currency + " " + DeepSeekWallet.amount(wallet.granted),size:10,width:204))
                for other in wallets where other.currency != wallet.currency { card.addArrangedSubview(text(L("另一币种    ") + other.displayAmount,size:10,secondary:true,width:204)) }
                if reading.balance?.isAvailable == false { card.addArrangedSubview(text(L("官方接口标记当前余额不足以调用 API"),size:10,secondary:true,width:204)) }
            } else { card.addArrangedSubview(text(reading.refreshing ? L("正在查询…") : "—",size:20,bold:true,width:204)) }
            if let error = reading.error ?? model.sourceError { card.addArrangedSubview(text(error,size:10,secondary:true,width:204)) }
            let formatter = DateFormatter(); formatter.locale = Localization.shared.locale; formatter.timeStyle = .medium
            let time = reading.lastSuccess.map { formatter.string(from:$0) } ?? L("尚未成功")
            card.addArrangedSubview(text(L("更新：") + time + L(" · 每 2 分钟检查"),size:10,secondary:true,width:204))
            card.layoutSubtreeIfNeeded()
            root.addArrangedSubview(GlassAppearance.card(card,width:220,height:card.fittingSize.height))
        }
        return root
    }
    private static func icon(_ symbol: String, label: String, id: String, handler: @escaping () -> Void) -> NSButton {
        let button = AccountActionButton("",id:id,handler:handler)
        button.image = NSImage(systemSymbolName:symbol,accessibilityDescription:label)
        button.imagePosition = .imageOnly; button.isBordered = false
        button.toolTip = label; button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant:22).isActive = true
        button.heightAnchor.constraint(equalToConstant:22).isActive = true
        return button
    }
}
