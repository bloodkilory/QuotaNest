import Foundation
enum QuotaProviderID: String, CaseIterable {
    case codex, claude, antigravity, kimi, zcode, minimax, qoder, codebuddy
    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .antigravity: return "Antigravity"
        case .kimi: return "Kimi Code"
        case .zcode: return "智谱 ZCode"
        case .minimax: return "MiniMax Code"
        case .qoder: return "Qoder"
        case .codebuddy: return "腾讯 CodeBuddy"
        }
    }
    var experimental: Bool { ![Self.codex, .claude, .antigravity].contains(self) }
    var loginHelp: String {
        switch self {
        case .codex: return L("使用本机 Codex 官方登录。")
        case .claude: return L("优先使用 Claude 桌面端当前账号；Claude Code 仅作同账号备用。")
        case .antigravity: return L("使用本机 Antigravity CLI 登录，胶囊默认展示 Gemini。")
        case .kimi: return L("请先在 Kimi Code 官方客户端完成国内账号登录。")
        case .zcode: return L("请先在官方 ZCode 登录智谱个人账号并连接 Coding Plan 或 Start Plan。仅复用已有登录，不创建 API Key。")
        case .minimax: return L("请先在官方 MiniMax Code 登录国内个人账号。")
        case .qoder: return L("需要 Node.js 与兼容的全球版官方 npm Qoder CLI（已核对 1.1.68），通过浏览器登录；暂不支持原生安装版。")
        case .codebuddy: return L("需要 VS Code 默认配置中的腾讯 CodeBuddy 官方扩展国内个人账号登录。首次读取需手动授权钥匙串；暂不支持独立 CLI 登录。")
        }
    }
}
struct ProviderReading {
    var snapshot: QuotaSnapshot?
    var modelID: String?
    var models: [(id: String, key: String, name: String, bucket: QuotaBucket)] {
        let entries = snapshot?.namedBuckets.filter { !$0.1.windows.isEmpty } ?? []
        return entries.map { key, bucket in
            let name = bucket.nameKey == nil && bucket.limitName == nil && bucket.limitId == nil ? key : bucket.displayName
            // Native responses may reorder indexed groups; public model names survive that reorder.
            let named = bucket.nameKey == nil && bucket.limitName != nil && entries.filter { $0.1.limitName == bucket.limitName }.count == 1
            return (named ? "name:" + bucket.limitName! : "key:" + key, key, name, bucket)
        }
    }
    var selectedModel: (id: String, key: String, name: String, bucket: QuotaBucket)? { models.first { $0.id == modelID } }
    var lastSuccess: Date?
    var failure: Error?
    private var errorText: String?
    var error: String? {
        get { failure?.localizedDescription ?? errorText.map { L($0) } }
        set { failure = nil; errorText = newValue }
    }
    var refreshing = false
    var successes = 0
    init(snapshot: QuotaSnapshot? = nil) { self.snapshot = snapshot }
    func remaining(for provider: QuotaProviderID) -> Double? {
        if let selectedModel { return selectedModel.bucket.remaining }
        if provider == .codex { return snapshot?.remaining }
        if provider == .qoder { return windows(for: provider).compactMap { $0.remaining }.min() }
        if provider == .antigravity {
            // Never substitute another model family's quota when Gemini is unavailable.
            return snapshot?.buckets.filter {
                $0.limitName?.range(of: #"\bgemini\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            }.compactMap { $0.remaining }.min()
        }
        return snapshot?.buckets.compactMap { $0.remaining }.min()
    }
}

enum QuotaPeriod: String, CaseIterable {
    case short, daily, weekly, billing
    func includes(_ window: QuotaWindow) -> Bool {
        if self == .billing { return window.minutes == nil }
        guard let minutes = window.minutes else { return false }
        if self == .daily { return minutes == 1440 }
        return self == .weekly ? minutes == 10080 : minutes > 0 && minutes < 1440
    }
}
extension ProviderReading {
    func windows(for provider: QuotaProviderID) -> [QuotaWindow] {
        if let selectedModel { return selectedModel.bucket.windows.filter { $0.remaining != nil } }
        let buckets: [QuotaBucket]
        switch provider {
        case .codex: buckets = snapshot?.selected.map { [$0.1] } ?? []
        case .claude, .kimi, .zcode, .minimax, .codebuddy: buckets = snapshot?.buckets ?? []
        case .qoder:
            // Add-ons are independent resources, not simultaneous subscription limits.
            buckets = ["qoder", "qoder-addon", "qoder-org"].compactMap { snapshot?.rateLimitsByLimitId?[$0] }.prefix(1).map { $0 }
        case .antigravity:
            buckets = snapshot?.buckets.filter {
                $0.limitName?.range(of: #"\bgemini\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            } ?? []
        }
        return buckets.flatMap { $0.windows }.filter { $0.remaining != nil }
    }
    func periods(for provider: QuotaProviderID) -> [QuotaPeriod] {
        QuotaPeriod.allCases.filter { period in windows(for: provider).contains(where: period.includes) }
    }
    func period(for provider: QuotaProviderID, preferred: QuotaPeriod) -> QuotaPeriod? {
        let available = periods(for: provider)
        return available.contains(preferred) ? preferred : available.first
    }
    func window(for provider: QuotaProviderID, period: QuotaPeriod?) -> QuotaWindow? {
        guard let period else { return nil }
        return windows(for: provider).filter(period.includes).min { ($0.remaining ?? 100) < ($1.remaining ?? 100) }
    }
    func periodLabel(for provider: QuotaProviderID, period: QuotaPeriod?) -> String {
        guard let period, let window = window(for: provider, period: period) else { return "—" }
        if period == .billing { return L("额") }
        guard let minutes = window.minutes else { return "—" }
        if period == .weekly { return "1w" }
        if period == .daily { return "1d" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)m"
    }
}
