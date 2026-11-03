import Foundation
struct QuotaWindow: Decodable {
    enum CodingKeys: String, CodingKey { case usedPercent, windowDurationMins, resetsAt, periodLabel, expiresAt }
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Double?
    var periodLabel: String? = nil
    var localizesPeriodLabel: Bool = false
    var expiresAt: Double? = nil
    var remaining: Double? { usedPercent.flatMap { $0.isFinite ? min(100, max(0, 100 - $0)) : nil } }
    var minutes: Int? { windowDurationMins }
    var title: String {
        if let periodLabel { return localizesPeriodLabel ? L(periodLabel) : periodLabel }
        guard let n = minutes else { return L("额度窗口") }
        if n % 1440 == 0 { return L("%@ 天额度", String(n / 1440)) }
        if n % 60 == 0 { return L("%@ 小时额度", String(n / 60)) }
        return L("%@ 分钟额度", String(n))
    }
}
struct Credits: Decodable { let balance: String?; let unlimited: Bool? }
struct QuotaBucket: Decodable {
    enum CodingKeys: String, CodingKey { case limitId, limitName, planType, primary, secondary, credits }
    let limitId: String?
    let limitName: String?
    let planType: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let credits: Credits?
    var nameKey: String? = nil
    var nameArguments: [String] = []
    var displayName: String { nameKey.map { Localization.shared.text($0,nameArguments) } ?? limitName ?? limitId ?? "—" }
    var windows: [QuotaWindow] { [primary, secondary].compactMap { $0 } }
    var remaining: Double? { windows.compactMap { $0.remaining }.min() }
}
struct QuotaSnapshot: Decodable {
    enum CodingKeys: String, CodingKey { case rateLimits, rateLimitsByLimitId }
    var loginSource: String? = nil
    let rateLimits: QuotaBucket?
    let rateLimitsByLimitId: [String: QuotaBucket]?
    var namedBuckets: [(String, QuotaBucket)] {
        if let map = rateLimitsByLimitId, !map.isEmpty { return map.keys.sorted().map { ($0, map[$0]!) } }
        return rateLimits.map { [($0.limitId ?? "codex", $0)] } ?? []
    }
    var buckets: [QuotaBucket] { namedBuckets.map { $0.1 } }
    var selected: (String, QuotaBucket)? { namedBuckets.first { $0.0 == "codex" } ?? namedBuckets.first { $0.1.remaining != nil } ?? namedBuckets.first }
    var remaining: Double? { selected?.1.remaining }
    static func decode(_ data: Data) throws -> QuotaSnapshot { try JSONDecoder().decode(Self.self, from: data) }
}
