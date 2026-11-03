import AppKit

enum OfficialQuotaView {
    static func build(provider: QuotaProviderID, reading: ProviderReading, displayedPeriod: QuotaPeriod?, selectModel: @escaping (String?) -> Void = { _ in }, authorize: @escaping () -> Void) -> NSStackView {
        let selectedProvider = provider
        let snapshot = reading.snapshot, errorMessage = reading.error, refreshing = reading.refreshing
        let lastSuccess = reading.lastSuccess
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        if selectedProvider.experimental {
            stack.addArrangedSubview(label(L(selectedProvider == .zcode ? "实验性接入" : "实验性接入 · 尚未用真实账号验证"), size: 11, color: .systemOrange))
        }
        stack.toolTip = selectedProvider.loginHelp
        if snapshot == nil || errorMessage != nil { stack.addArrangedSubview(label(selectedProvider.loginHelp, color:.secondaryLabelColor)) }
        if let selected = snapshot?.selected {
            let source = selectedProvider == .codex ? (selected.1.planType ?? L("Codex 登录账号")) : L("本机 ") + selectedProvider.title + L(" 官方登录")
            stack.toolTip! += "\n" + source + L(" · 胶囊：") + (reading.selectedModel.map { $0.name + " " } ?? (selectedProvider == .antigravity ? "Gemini " : "")) + reading.periodLabel(for:selectedProvider,period:displayedPeriod)
        }
        if let errorMessage { stack.addArrangedSubview(label("⚠ \(errorMessage)" + (snapshot == nil ? "" : L("\n当前百分比为上次成功查询结果。")), color: .systemOrange)) }
        if let snapshot {
            if let source = snapshot.loginSource { stack.addArrangedSubview(label(L("登录来源：%@",L(source)),color:.secondaryLabelColor)) }
            let models = reading.models
            let showModelChoice = models.count > 1 || reading.selectedModel != nil
            func radio(_ title: String, id: String?) -> NSButton {
                let button = AccountActionButton(title,id:"quota-model-" + (id ?? "automatic"),handler:{ selectModel(id) })
                button.setButtonType(.radio); button.controlSize = .small; button.font = .systemFont(ofSize:11)
                button.state = reading.selectedModel?.id == id ? .on : .off
                button.lineBreakMode = .byTruncatingTail; button.toolTip = title
                button.setAccessibilityLabel(L("在胶囊中显示：%@",title))
                button.widthAnchor.constraint(equalToConstant:220).isActive = true
                return button
            }
            if showModelChoice {
                stack.addArrangedSubview(label(L("胶囊显示额度"),color:.secondaryLabelColor))
                let automatic = radio(L("自动（默认）"),id:nil)
                automatic.toolTip = L("按平台默认规则显示额度")
                stack.addArrangedSubview(automatic)
            }
            for (key, bucket) in snapshot.namedBuckets {
                let heading = bucket.nameKey == nil && bucket.limitName == nil && bucket.limitId == nil ? key : bucket.displayName
                if showModelChoice, let model = models.first(where:{ $0.key == key }) {
                    stack.addArrangedSubview(radio(heading,id:model.id))
                } else if snapshot.namedBuckets.count > 1 || heading.lowercased() != selectedProvider.title.lowercased() {
                    stack.addArrangedSubview(label(heading,size:11,bold:true))
                }
                if bucket.windows.isEmpty { stack.addArrangedSubview(label(L("暂无可用额度窗口"), color: .secondaryLabelColor)) }
                for window in bucket.windows {
                    let value = window.remaining.map { String(format: "%.1f%%", $0) } ?? L("未知")
                    stack.addArrangedSubview(label(L("%@    剩余 %@",window.title,value), size: 12, bold: true))
                    let expiration = window.expiresAt != nil || (window.localizesPeriodLabel && window.periodLabel == "一次性额度")
                    stack.addArrangedSubview(label(expiration ? expiryText(window.expiresAt) : resetText(window.resetsAt),color:.secondaryLabelColor))
                    let bar = NSProgressIndicator(); bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 100; bar.doubleValue = window.remaining ?? 0
                    bar.controlSize = .small
                    bar.widthAnchor.constraint(equalToConstant: 220).isActive = true
                    if window.remaining != nil { stack.addArrangedSubview(bar) }
                }
                if let credits = bucket.credits {
                    stack.addArrangedSubview(label(L("Credits 余额：%@",credits.unlimited == true ? L("无限") : credits.balance ?? L("未提供")), color: .secondaryLabelColor))
                }
            }
        } else { stack.addArrangedSubview(label(refreshing ? L("正在读取官方套餐…") : L("尚未取得额度"), color: .secondaryLabelColor)) }
        let time = lastSuccess.map { dateString($0) } ?? L("尚未成功")
        stack.addArrangedSubview(label(L("更新：") + time,color:.secondaryLabelColor))
        stack.toolTip! += "\n" + L("更新：%@\n每 2 分钟刷新 · %@",time,TimeZone.current.identifier)
        if selectedProvider == .claude && errorMessage != nil {
            let authorize = AccountActionButton(L("授权 Claude 登录读取"),handler:authorize)
            authorize.controlSize = .small; authorize.font = .systemFont(ofSize:11)
            authorize.widthAnchor.constraint(equalToConstant:220).isActive = true
            authorize.isEnabled = !refreshing; stack.addArrangedSubview(authorize)
        }
        if selectedProvider == .codebuddy && errorMessage != nil {
            let authorize = AccountActionButton(L("授权 CodeBuddy 登录读取"),handler:authorize)
            authorize.controlSize = .small; authorize.font = .systemFont(ofSize:11)
            authorize.widthAnchor.constraint(equalToConstant:220).isActive = true
            authorize.isEnabled = !refreshing; stack.addArrangedSubview(authorize)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant:220).isActive = true
        return stack
    }
    private static func label(_ value: String, size: CGFloat = 10, color: NSColor = .labelColor, bold: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        field.textColor = color
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return field
    }
    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Localization.shared.locale; formatter.dateFormat = "MM-dd HH:mm"; return formatter.string(from: date)
    }
    private static func expiryText(_ timestamp: Double?) -> String {
        guard let timestamp, timestamp.isFinite, timestamp > 0, timestamp <= 253402300799 else { return L("到期时间：未提供") }
        return L("到期：%@",dateString(Date(timeIntervalSince1970:timestamp)))
    }
    private static func resetText(_ timestamp: Double?) -> String {
        guard let timestamp, timestamp.isFinite, timestamp > 0, timestamp <= 253402300799 else { return L("重置时间：未提供") }
        let date = Date(timeIntervalSince1970: timestamp), seconds = date.timeIntervalSinceNow
        if seconds <= 0 { return L("重置：%@ · 等待服务更新",dateString(date)) }
        let hours = Int(seconds / 3600), minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        return L("重置：%@\n还有 %@ 天 %@ 小时 %@ 分钟",dateString(date),String(hours / 24),String(hours % 24),String(minutes))
    }
}
