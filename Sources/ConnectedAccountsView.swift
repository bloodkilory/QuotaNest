import AppKit
import QuartzCore

class AccountActionButton: NSButton {
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

final class RefreshIconButton: AccountActionButton {
    static let spinAnimationKey = "quotanest.refresh.spin"
    private let spinnerView = NSImageView()
    private let fallbackHost = NSView()
    private let fallbackLayer = CALayer()
    private var symbolEffectActive = false
    var isSpinning = false { didSet { updateSpinner() } }
    var hasSpinAnimation: Bool {
        if #available(macOS 15.0, *) { return symbolEffectActive }
        return fallbackLayer.animation(forKey: Self.spinAnimationKey) != nil
    }

    init(symbol: String, label: String, id: String, spinning: Bool, handler: @escaping () -> Void) {
        super.init("", id: id, handler: handler)
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        image = icon
        imagePosition = .imageOnly
        isBordered = false
        contentTintColor = .labelColor
        toolTip = label
        setAccessibilityLabel(label)
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true

        if #available(macOS 15.0, *) {
            spinnerView.image = icon
            spinnerView.imageAlignment = .alignCenter
            spinnerView.imageScaling = .scaleNone
            spinnerView.contentTintColor = .labelColor
            spinnerView.isHidden = true
            addSubview(spinnerView)
        } else {
            // macOS 13–14：使用纯 CALayer 子层围绕中心原地旋转，避免 AppKit 重置 NSView backing layer 的 anchorPoint。
            fallbackHost.wantsLayer = true
            fallbackHost.isHidden = true
            fallbackLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            fallbackLayer.contentsGravity = .center
            fallbackHost.layer?.addSublayer(fallbackLayer)
            addSubview(fallbackHost)
        }
        isSpinning = spinning
        updateSpinner()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // 旋转中由居中的旋转视图绘制图标，避免静态底层重影。
        if isSpinning { return }
        super.draw(dirtyRect)
    }

    override func layout() {
        super.layout()
        syncSpinnerGeometry()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateSpinner()
    }

    private func syncSpinnerGeometry() {
        let size = bounds.size.width > 0 && bounds.size.height > 0 ? bounds.size : NSSize(width: 22, height: 22)
        if #available(macOS 15.0, *) {
            spinnerView.frame = NSRect(origin: .zero, size: size)
        } else {
            fallbackHost.frame = NSRect(origin: .zero, size: size)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fallbackLayer.bounds = CGRect(origin: .zero, size: size)
            fallbackLayer.position = CGPoint(x: size.width / 2, y: size.height / 2)
            fallbackLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            if let img = image {
                var rect = NSRect(origin: .zero, size: img.size)
                fallbackLayer.contents = img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            }
            CATransaction.commit()
        }
    }

    private func updateSpinner() {
        needsDisplay = true
        syncSpinnerGeometry()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if #available(macOS 15.0, *) {
            spinnerView.isHidden = !isSpinning
            if isSpinning && !reduceMotion {
                if !symbolEffectActive {
                    spinnerView.addSymbolEffect(.rotate.clockwise, options: .repeat(.continuous))
                    symbolEffectActive = true
                }
            } else if symbolEffectActive {
                spinnerView.removeAllSymbolEffects()
                symbolEffectActive = false
            }
            return
        }
        fallbackHost.isHidden = !isSpinning
        if !isSpinning || reduceMotion {
            fallbackLayer.removeAnimation(forKey: Self.spinAnimationKey)
            return
        }
        if fallbackLayer.animation(forKey: Self.spinAnimationKey) == nil {
            let duration: CFTimeInterval = 0.85
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = 0
            animation.toValue = -CGFloat.pi * 2
            animation.duration = duration
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.timeOffset = CACurrentMediaTime().truncatingRemainder(dividingBy: duration)
            fallbackLayer.add(animation, forKey: Self.spinAnimationKey)
        }
    }
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
        let refresh = RefreshIconButton(symbol:"arrow.clockwise",label:L(refreshing ? "正在刷新…" : "立即刷新"),id:refreshID,spinning:refreshing) { actions.refresh(accountID) }
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
        button.contentTintColor = .labelColor
        button.toolTip = label; button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant:22).isActive = true
        button.heightAnchor.constraint(equalToConstant:22).isActive = true
        return button
    }
}
