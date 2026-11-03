import AppKit
final class AppController: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem!
    private let capsule = CapsuleView(frame: NSRect(x: 0, y: 0, width: 64, height: 24))
    private let popover = NSPopover()
    private let client = CodexClient()
    private var timer: Timer?
    private let claudeClient = ClaudeQuotaClient()
    private let antigravityClient = AntigravityQuotaClient()
    private let kimiClient = KimiQuotaClient()
    private let zcodeClient = ZCodeQuotaClient()
    private let minimaxClient = MiniMaxQuotaClient()
    private let qoderClient = QoderQuotaClient()
    private let codebuddyClient = CodeBuddyQuotaClient()
    private let updateClient = ReleaseUpdateClient()
    private var connectionStore: CCSwitchStore = {
        let standard = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cc-switch")
        let directory = UserDefaults.standard.string(forKey:"ccSwitchDirectory").map { URL(fileURLWithPath:$0) } ?? standard
        return CCSwitchStore(directory:directory,liveDirectory:standard)
    }()
    private lazy var balanceClient = DeepSeekBalanceClient(store:connectionStore)
    private let sourceQueue = DispatchQueue(label:"local.quotanest.cc-switch")
    private var connections: [CCSwitchConnection] = []
    private var accountReadings: [String:ConnectedAccountReading] = [:]
    private var linkedConnections = Set(UserDefaults.standard.stringArray(forKey:"ccSwitchConnections") ?? [])
    private var sourceConnected = UserDefaults.standard.bool(forKey:"ccSwitchConnected")
    private let displaySelection = DisplaySelection()
    private var previewProvider: QuotaProviderID?
    private var pinnedConnection: String? { previewProvider == nil ? displaySelection.accountID : nil }
    private var sourceFailure: Error?
    private var sourceError: String? { sourceFailure?.localizedDescription }
    private var discoveringSource = false
    private var chooseAfterDiscovery = false
    private var showingSettings = false
    private var sourceEpoch = 0
    private let updateInstaller = UpdateInstaller(helperDigest:BundledUpdateHelperIdentity.sha256)
    private var updateState = UpdateMenuState.busy("正在检查更新…")
    private var updateRelease: UpdateRelease?
    private var previousUpdateMessage: UpdateInstallStatus?
    private var currentVersion: DottedVersion? { DottedVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") }
    private var readings = Dictionary(uniqueKeysWithValues: QuotaProviderID.allCases.map { ($0, ProviderReading()) })
    private var selectedProvider: QuotaProviderID { previewProvider ?? displaySelection.provider }
    private func preferredPeriod(for provider: QuotaProviderID) -> QuotaPeriod {
        QuotaPeriod(rawValue: UserDefaults.standard.string(forKey: "quotaPeriod." + provider.rawValue) ?? "") ?? .short
    }
    private var displayedPeriod: QuotaPeriod? { reading.period(for: selectedProvider, preferred: preferredPeriod(for: selectedProvider)) }
    private func switchPeriod() {
        if let id = pinnedConnection {
            let wallets = accountReadings[id]?.balance?.wallets ?? []
            guard wallets.count > 1 else { return }
            let current = accountWallet(id)?.currency
            let index = wallets.firstIndex { $0.currency == current } ?? 0
            UserDefaults.standard.set(wallets[(index + 1) % wallets.count].currency,forKey:"balanceCurrency." + id)
            render(); writeDiagnostics(); return
        }
        let periods = reading.periods(for: selectedProvider)
        guard periods.count > 1, let current = displayedPeriod, let index = periods.firstIndex(of: current) else { return }
        UserDefaults.standard.set(periods[(index + 1) % periods.count].rawValue, forKey: "quotaPeriod." + selectedProvider.rawValue)
        render(); writeDiagnostics()
    }
    private func reading(for provider: QuotaProviderID) -> ProviderReading {
        var value = readings[provider]!
        value.modelID = displaySelection.model(for:provider)
        return value
    }
    private var reading: ProviderReading { reading(for:selectedProvider) }
    private var snapshot: QuotaSnapshot? { reading.snapshot }
    private var lastSuccess: Date? { reading.lastSuccess }
    private var errorMessage: String? { reading.error }
    private var refreshing: Bool { reading.refreshing }
    private var lockHandle: FileHandle?
    private let interval: TimeInterval = 120
    private var stateDirectory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexQuota") }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // flock survives PID reuse and releases automatically on exit.
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let lockURL = stateDirectory.appendingPathComponent("instance.lock")
        if !FileManager.default.fileExists(atPath: lockURL.path) { FileManager.default.createFile(atPath: lockURL.path, contents: nil) }
        lockHandle = try? FileHandle(forWritingTo: lockURL)
        if !CommandLine.arguments.contains("--preview") {
            guard let lockHandle, flock(lockHandle.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else { NSApp.terminate(nil); return }
        }
        // Keep the existing login preference while updating its executable path after a rename/move.
        if !CommandLine.arguments.contains("--preview"), LoginItemManager.enabled,
           !Bundle.main.bundlePath.hasPrefix("/Volumes/") {
            try? LoginItemManager.setEnabled(true)
        }
        status = NSStatusBar.system.statusItem(withLength: 64)
        if let button = status.button {
            capsule.frame = button.bounds; capsule.autoresizingMask = [.width, .height]
            button.addSubview(capsule)
        }
        capsule.action = { [weak self] in self?.togglePopover() }
        capsule.periodAction = { [weak self] in self?.switchPeriod() }
        popover.behavior = .transient
        popover.animates = true
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        self.timer = timer; timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(accessibilityChanged),name:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(languageChanged),name:Localization.changed,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(languageChanged),name:NSLocale.currentLocaleDidChangeNotification,object:nil)
        refresh()
        if !CommandLine.arguments.contains("--preview") { readPreviousUpdateStatus(); checkForUpdate() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); client.shutdown(); claudeClient.shutdown(); antigravityClient.shutdown()
        kimiClient.shutdown(); zcodeClient.shutdown(); minimaxClient.shutdown(); qoderClient.shutdown(); codebuddyClient.shutdown()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        updateClient.cancel()
        balanceClient.shutdown()
    }
    @objc private func languageChanged() { render() }
    @objc private func woke() { refresh() }
    @objc private func accessibilityChanged() { capsule.needsDisplay = true; if popover.isShown { buildPopover() } }
    @objc private func refresh() {
        for provider in QuotaProviderID.allCases { refresh(provider) }
        if sourceConnected { discoverConnections() }
    }
    private func accountWallet(_ id: String) -> DeepSeekWallet? {
        guard sourceConnected, linkedConnections.contains(id), connections.contains(where:{ $0.id == id && $0.supportsBalance }) else { return nil }
        let wallets = accountReadings[id]?.balance?.wallets ?? []
        let preferred = UserDefaults.standard.string(forKey:"balanceCurrency." + id)
        return wallets.first { $0.currency == preferred } ?? wallets.first
    }
    private func discoverConnections(choose: Bool = false) {
        chooseAfterDiscovery = chooseAfterDiscovery || choose
        guard !discoveringSource else { return }
        discoveringSource = true
        let store = connectionStore
        let epoch = sourceEpoch
        sourceQueue.async {
            let result = Result { try store.discover() }
            DispatchQueue.main.async {
                guard self.sourceEpoch == epoch else { return }
                self.discoveringSource = false
                let shouldChoose = self.chooseAfterDiscovery; self.chooseAfterDiscovery = false
                switch result {
                case .success(let values):
                    self.connections = values; self.sourceFailure = nil
                    for id in self.accountReadings.keys { self.accountReadings[id]?.reconcile(with:values.first { $0.id == id }) }
                    if shouldChoose { self.chooseConnections() }
                    if self.sourceConnected {
                        for entry in values where self.linkedConnections.contains(entry.id) && entry.supportsBalance { self.refreshAccount(entry.id) }
                    }
                case .failure(let error):
                    self.sourceFailure = error
                    for id in self.accountReadings.keys { self.accountReadings[id]?.discoveryFailed(error) }
                    if shouldChoose { self.chooseConnections() }
                }
                self.render(); self.writeDiagnostics()
            }
        }
    }
    private func refreshAccount(_ id: String) {
        guard sourceConnected, linkedConnections.contains(id), connections.contains(where:{ $0.id == id && $0.supportsBalance }) else { return }
        if accountReadings[id] == nil { accountReadings[id] = ConnectedAccountReading() }
        guard let generation = accountReadings[id]?.begin() else { return }
        let epoch = sourceEpoch
        balanceClient.fetch(connectionID:id,onSourceChange:{
            DispatchQueue.main.async {
                guard self.sourceEpoch == epoch, self.accountReadings[id]?.generation == generation else { return }
                self.accountReadings[id]?.sourceChanged(); self.render()
            }
        }) { result in
            DispatchQueue.main.async {
                guard self.sourceEpoch == epoch, self.linkedConnections.contains(id), self.accountReadings[id]?.complete(result,generation:generation) == true else { return }
                self.render(); self.writeDiagnostics()
            }
        }
        render()
    }
    private func chooseConnections() {
        let alert = NSAlert(); alert.messageText = L("连接 CC Switch 已有服务")
        alert.informativeText = sourceError ?? L("只读所选连接及其已有凭据，不修改 CC Switch。DeepSeek 凭据仅发往 api.deepseek.com 查询余额，不调用模型、不保存 Key。其他服务目前仅识别配置。")
        alert.addButton(withTitle:L("连接所选")); alert.addButton(withTitle:L("取消")); alert.addButton(withTitle:L("选择数据目录…"))
        let list = ConnectedAccountsView.stack(width:360,spacing:8)
        var choices: [(String,NSButton)] = []
        for entry in connections {
            let title = entry.displayName + " · " + (entry.harness == "claude" ? "Claude Code" : "Codex") + (entry.supportsBalance ? L(" · 可查余额") : L(" · 仅识别"))
            let check = NSButton(checkboxWithTitle:title,target:nil,action:nil)
            check.lineBreakMode = .byTruncatingTail; check.toolTip = title
            check.widthAnchor.constraint(lessThanOrEqualToConstant:360).isActive = true
            check.state = linkedConnections.contains(entry.id) ? .on : .off
            list.addArrangedSubview(check); choices.append((entry.id,check))
        }
        list.layoutSubtreeIfNeeded()
        let height = max(40,list.fittingSize.height); list.frame = NSRect(x:0,y:0,width:360,height:height)
        let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:360,height:min(260,height)))
        scroll.drawsBackground = false; scroll.hasVerticalScroller = height > 260; scroll.documentView = list
        scroll.contentView.scroll(to:NSPoint(x:0,y:max(0,height - scroll.frame.height)))
        alert.accessoryView = scroll
        let response = alert.runModal()
        if response == .alertThirdButtonReturn {
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
            panel.message = L("选择包含 cc-switch.db 的 CC Switch 数据目录"); panel.prompt = L("选择")
            guard panel.runModal() == .OK, let directory = panel.url else { return }
            balanceClient.shutdown()
            sourceEpoch += 1
            discoveringSource = false; chooseAfterDiscovery = false
            connectionStore = CCSwitchStore(directory:directory,liveDirectory:FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cc-switch"))
            balanceClient = DeepSeekBalanceClient(store:connectionStore)
            linkedConnections = []; accountReadings = [:]; connections = []; sourceConnected = false
            UserDefaults.standard.set(directory.path,forKey:"ccSwitchDirectory")
            saveConnections(); discoverConnections(choose:true); return
        }
        guard response == .alertFirstButtonReturn, sourceError == nil else { return }
        linkedConnections = Set(choices.filter { $0.1.state == .on }.map { $0.0 })
        sourceConnected = !linkedConnections.isEmpty
        for id in accountReadings.keys where !linkedConnections.contains(id) { accountReadings[id]?.invalidate() }
        saveConnections()
    }
    private func saveConnections() {
        UserDefaults.standard.set(Array(linkedConnections).sorted(),forKey:"ccSwitchConnections")
        UserDefaults.standard.set(sourceConnected,forKey:"ccSwitchConnected")
    }
    @objc private func manualRefresh() { refresh(selectedProvider) }
    @objc private func authorizeClaude() { refresh(.claude, allowPrompt: true) }
    @objc private func authorizeCodeBuddy() { refresh(.codebuddy, allowPrompt: true) }
    private func showUpdateState(_ state: UpdateMenuState) {
        updateState = state
        if popover.isShown { buildPopover() }
    }
    @objc private func checkForUpdate() {
        guard let version = currentVersion else { showUpdateState(.failed(UpdateError("无法识别当前应用版本"))); return }
        updateRelease = nil; showUpdateState(.busy("正在检查更新…"))
        updateClient.check(currentVersion:version) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(.upToDate): self.showUpdateState(.current(version.text))
                case .success(.available(let release)): self.updateRelease = release; self.showUpdateState(.available(release.version.text))
                case .failure(let error): self.showUpdateState(.failed(error))
                }
            }
        }
    }
    @objc private func installUpdate() {
        guard updateState.isActionEnabled, let release = updateRelease, let version = currentVersion else { return }
        showUpdateState(.busy("正在下载并校验安装包…"))
        updateClient.download(release) { [weak self] result in
            switch result {
            case .failure(let error): DispatchQueue.main.async { self?.showUpdateState(.failed(error)) }
            case .success(let dmg):
                DispatchQueue.main.async { self?.showUpdateState(.busy("正在验证更新应用…")) }
                self?.updateInstaller.stage(dmg,currentVersion:version) { preparedResult in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        switch preparedResult {
                        case .failure(let error): self.showUpdateState(.failed(error))
                        case .success(let prepared): self.confirmUpdate(prepared,release:release)
                        }
                    }
                }
            }
        }
    }
    private func confirmUpdate(_ prepared: PreparedUpdate, release: UpdateRelease) {
        popover.performClose(nil)
        let alert = NSAlert(); alert.messageText = L("安装余度 QuotaNest v%@？",release.version.text)
        alert.informativeText = L("下载及校验已完成。应用将退出、保留旧版本备份并安装更新，随后重新打开。") + (prepared.target.isUser ? "" : L("\n需要时 macOS 会请求管理员授权。"))
        alert.addButton(withTitle:L("安装并重启")); alert.addButton(withTitle:L("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { UpdatePaths.clean(prepared.directory); showUpdateState(.available(release.version.text)); return }
        showUpdateState(.busy("正在准备安装，请完成系统授权…"))
        UserDefaults.standard.set(prepared.directory.path,forKey:"pendingUpdateDirectory")
        UpdatePrivilegeLauncher.launch(prepared) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success: NSApp.terminate(nil)
                case .failure(let error): self?.showUpdateState(.failed(error))
                }
            }
        }
    }
    private func readPreviousUpdateStatus() {
        guard let path = UserDefaults.standard.string(forKey:"pendingUpdateDirectory") else { return }
        let directory = URL(fileURLWithPath:path)
        guard UpdatePaths.samePath(directory.deletingLastPathComponent(),UpdatePaths.root()), directory.lastPathComponent.hasPrefix("stage.") else { return }
        if let data = try? Data(contentsOf:directory.appendingPathComponent("status.json")), data.count <= 16384,
           let status = try? JSONDecoder().decode(UpdateInstallStatus.self,from:data), ["failed","installed"].contains(status.state) {
            previousUpdateMessage = status
            UserDefaults.standard.removeObject(forKey:"pendingUpdateDirectory")
            UpdatePaths.clean(directory)
        }
    }
    private func refresh(_ provider: QuotaProviderID, allowPrompt: Bool = false) {
        guard readings[provider]?.refreshing != true else { return }
        readings[provider]?.refreshing = true
        render()
        let completion: (Result<QuotaSnapshot, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.readings[provider]?.refreshing = false
                switch result {
                case .success(let value):
                    self.readings[provider]?.snapshot = value
                    self.readings[provider]?.lastSuccess = Date()
                    self.readings[provider]?.successes += 1
                    self.readings[provider]?.error = nil
                case .failure(let error): self.readings[provider]?.failure = error
                }
                self.render(); self.writeDiagnostics()
                if CommandLine.arguments.contains("--preview") && !self.readings.values.contains(where: { $0.refreshing }) { self.exportPreview() }
            }
        }
        switch provider {
        case .codex: client.fetch(completion)
        case .claude: claudeClient.fetch(allowPrompt:allowPrompt,onAccountChange:{ [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.readings[.claude]?.snapshot = nil; self.readings[.claude]?.lastSuccess = nil; self.readings[.claude]?.failure = nil
                self.render(); self.writeDiagnostics()
            }
        },completion:completion)
        case .antigravity: antigravityClient.fetch(completion)
        case .kimi: kimiClient.fetch(completion)
        case .zcode: zcodeClient.fetch(completion: completion)
        case .minimax: minimaxClient.fetch(completion: completion)
        case .qoder: qoderClient.fetch(completion)
        case .codebuddy: codebuddyClient.fetch(allowPrompt: allowPrompt, completion: completion)
        }
    }
    private func selectSource(_ source: DisplaySource) {
        displaySelection.select(source)
        render(); writeDiagnostics()
    }
    private func exportPreview() {
        showingSettings = false
        NSApp.appearance = NSAppearance(named: .aqua)
        for provider in QuotaProviderID.allCases {
            previewProvider = provider
            buildPopover()
            guard let view = popover.contentViewController?.view else { continue }
            view.appearance = NSAppearance(named: .aqua)
            if let scroll = view as? NSScrollView { scroll.drawsBackground = true; scroll.backgroundColor = .white }
            let window = NSWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua); window.contentView = view
            window.layoutIfNeeded(); view.layoutSubtreeIfNeeded()
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: stateDirectory.appendingPathComponent("preview-" + provider.rawValue + ".png")) }
                }
            }
            popover.contentViewController = nil
        }
        NSApp.terminate(nil)
    }
    private func writeDiagnostics() {
        guard !CommandLine.arguments.contains("--preview") else { return }
        // Only non-identifying operational state, no account ID or authentication data.
        var providers: [String: Any] = [:]
        for provider in QuotaProviderID.allCases {
            let entry = reading(for:provider)
            var value: [String: Any] = ["successfulRefreshes": entry.successes, "refreshing": entry.refreshing]
            let period = entry.period(for: provider, preferred: preferredPeriod(for: provider))
            value["period"] = period?.rawValue ?? "unknown"
            if let remaining = entry.window(for: provider, period: period)?.remaining { value["remaining"] = remaining }
            if let model = entry.selectedModel { value["model"] = model.name }
            if let date = entry.lastSuccess { value["lastSuccess"] = ISO8601DateFormatter().string(from: date) }
            if let source = entry.snapshot?.loginSource { value["loginSource"] = source }
            if let error = entry.error { value["error"] = error }
            providers[provider.rawValue] = value
        }
        let accounts: [[String:Any]] = connections.filter { linkedConnections.contains($0.id) && $0.supportsBalance }.map { entry in
            let reading = accountReadings[entry.id] ?? ConnectedAccountReading()
            var status: [String:Any] = ["service":"DeepSeek","refreshing":reading.refreshing,"successfulRefreshes":reading.successes,"pinned":pinnedConnection == entry.id]
            if let date = reading.lastSuccess { status["lastSuccess"] = ISO8601DateFormatter().string(from:date) }
            if let error = reading.error { status["error"] = error }
            return status
        }
        let value: [String: Any] = ["providers": providers, "selectedProvider": selectedProvider.rawValue, "refreshIntervalSeconds": interval, "loginEnabled": LoginItemManager.enabled, "display": capsule.text, "pid": ProcessInfo.processInfo.processIdentifier,"ccSwitchConnected":sourceConnected,"apiAccounts":accounts]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: stateDirectory.appendingPathComponent("status.json"), options: .atomic) }
    }
    private func render() {
        if let id = pinnedConnection {
            let entry = accountReadings[id] ?? ConnectedAccountReading(), wallet = accountWallet(id)
            capsule.showsWallet = true; capsule.remaining = nil; capsule.periodText = wallet?.currency == "CNY" ? "¥" : wallet?.currency == "USD" ? "$" : "—"
            capsule.canSwitchPeriod = wallet != nil && (entry.balance?.wallets.count ?? 0) > 1
            capsule.stale = entry.error != nil || sourceError != nil || !connections.contains { $0.id == id && $0.supportsBalance && linkedConnections.contains(id) }
            capsule.text = wallet.map { $0.capsuleAmount + (capsule.stale ? "!" : "") } ?? (entry.refreshing ? "···" : "—")
            let sourceExists = connections.contains { $0.id == id } && linkedConnections.contains(id)
            let title = L("DeepSeek 官方 API 余额：") + (wallet?.displayAmount ?? L("尚无有效读数")) + (sourceExists ? "" : L("；来源已移除或不可读")) + (capsule.stale ? L("；上次数据已过期") : "")
            capsule.detailButton.toolTip = title; capsule.detailButton.setAccessibilityLabel(title + L("，打开账户详情"))
            capsule.periodButton.toolTip = capsule.canSwitchPeriod ? L("切换余额币种") : L("账户钱包余额")
            capsule.periodButton.setAccessibilityLabel(capsule.periodButton.toolTip!)
            if popover.isShown { buildPopover() }
            return
        }
        capsule.showsWallet = false
        let period = displayedPeriod
        let remaining = reading.window(for: selectedProvider, period: period)?.remaining
        capsule.periodText = reading.periodLabel(for: selectedProvider, period: period)
        capsule.canSwitchPeriod = reading.periods(for: selectedProvider).count > 1
        capsule.remaining = remaining; capsule.stale = errorMessage != nil
        let value = remaining.map { String(format: "%.0f%%", floor($0)) + (errorMessage == nil ? "" : "!") } ?? (refreshing ? "···" : "—")
        capsule.provider = selectedProvider
        capsule.text = value
        let title = L("%@ %@ 剩余额度 %@",selectedProvider.title + (reading.selectedModel.map { " · " + $0.name } ?? (selectedProvider == .antigravity ? " Gemini" : "")),capsule.periodText,value) + (errorMessage == nil ? "" : L("，查询失败或数据过期"))
        capsule.detailButton.setAccessibilityLabel(title + L("，打开详情"))
        capsule.detailButton.toolTip = title
        let periodHelp = L("当前 ") + capsule.periodText + (capsule.canSwitchPeriod ? L("，点击切换额度周期") : L("，暂无其他有效周期"))
        capsule.periodButton.setAccessibilityLabel(periodHelp)
        capsule.periodButton.toolTip = periodHelp
        if popover.isShown { buildPopover() }
    }
    private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        buildPopover()
        if let button = status.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
    }
    private func buildPopover() {
        let content: NSStackView
        if showingSettings { content = settingsContent() }
        else {
            let model = ConnectedAccountsPresentation(connections:connections,enabled:linkedConnections,readings:accountReadings,source:previewProvider.map { .official($0) } ?? displaySelection.source,currency:pinnedConnection.flatMap { UserDefaults.standard.string(forKey:"balanceCurrency." + $0) },sourceError:sourceError)
            content = ConnectedAccountsView.build(model,officialDetails:pinnedConnection == nil ? officialDetails() : nil,officialRefreshing:reading.refreshing,actions:ConnectedAccountsActions(
                select:{ self.selectSource($0) },
                refresh:{ if let id = $0 { self.refreshAccount(id) } else { self.manualRefresh() } },
                settings:{ self.showingSettings = true; self.buildPopover() }))
        }
        let focused = (popover.contentViewController?.view.window?.firstResponder as? NSView)?.identifier
        content.layoutSubtreeIfNeeded()
        let height = content.fittingSize.height
        let width: CGFloat = showingSettings ? 380 : ConnectedAccountsView.width
        let maxHeight = min(650,(status.button?.window?.screen?.visibleFrame.height ?? 730) - 80)
        content.frame = NSRect(x:0,y:0,width:width,height:height)
        let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:width,height:min(height,maxHeight)))
        scroll.drawsBackground = false; scroll.hasVerticalScroller = height > maxHeight; scroll.documentView = content
        scroll.contentView.scroll(to:NSPoint(x:0,y:max(0,height - scroll.frame.height)))
        let controller = NSViewController(); controller.view = GlassAppearance.wrap(scroll,size:scroll.frame.size)
        popover.contentViewController = controller; popover.contentSize = scroll.frame.size
        controller.view.window?.autorecalculatesKeyViewLoop = true
        if let focused {
            func find(_ view: NSView) -> NSView? { view.identifier == focused ? view : view.subviews.lazy.compactMap { find($0) }.first }
            if let target = find(controller.view) { controller.view.window?.makeFirstResponder(target) }
        }
    }
    private func officialDetails() -> NSStackView {
        OfficialQuotaView.build(provider:selectedProvider,reading:reading,displayedPeriod:displayedPeriod,
            selectModel:{ id in
                self.displaySelection.selectModel(id,for:self.selectedProvider)
                self.render(); self.writeDiagnostics()
            },
            authorize:{
                if self.selectedProvider == .claude { self.authorizeClaude() }
                else if self.selectedProvider == .codebuddy { self.authorizeCodeBuddy() }
            })
    }
    private func settingsContent() -> NSStackView {
        let model = SettingsPresentation(connections:connections,enabled:linkedConnections,sourceError:sourceError,discovering:discoveringSource,language:Localization.shared.preference,version:currentVersion?.text,updateState:updateState,previousStatus:previousUpdateMessage,availableVersion:updateRelease?.version.text,canInstall:(try? UpdateTarget.resolve(runningBundle:Bundle.main.bundleURL)) != nil,loginEnabled:LoginItemManager.enabled)
        return SettingsView.build(model,actions:SettingsActions(
            back:{ self.showingSettings = false; self.buildPopover() },
            language:{ Localization.shared.preference = $0 },
            connect:{ self.discoverConnections(choose:true) },
            checkUpdate:{ self.checkForUpdate() },installUpdate:{ self.installUpdate() },
            login:{ self.toggleLogin($0) },quit:{ self.quit() }))
    }
    private func toggleLogin(_ enabled: Bool) {
        do { try LoginItemManager.setEnabled(enabled); writeDiagnostics() }
        catch { let alert = NSAlert(); alert.messageText = L("无法更新登录项"); alert.informativeText = error.localizedDescription; alert.runModal() }
        render()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
