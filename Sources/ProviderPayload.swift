import Foundation
import CoreFoundation
struct ProviderPayloadError: LocalizedError {
    let message: String
    var arguments: [String] = []
    var errorDescription: String? { Localization.shared.text(message,arguments) }
}
enum ProviderPayload {
    static func timestamp(_ value: Any?) -> Double? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)?.timeIntervalSince1970
    }
    private static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderPayloadError(message: "额度响应格式无效") }
        return object
    }
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    static func claude(_ data: Data) throws -> QuotaSnapshot {
        let object = try object(data)
        func window(_ key: String, _ minutes: Int) -> QuotaWindow? {
            guard let row = object[key] as? [String: Any] else { return nil }
            return QuotaWindow(usedPercent: number(row["utilization"]), windowDurationMins: minutes, resetsAt: timestamp(row["resets_at"]))
        }
        var buckets: [String: QuotaBucket] = [:]
        let main = QuotaBucket(limitId: "claude", limitName: "Claude 官方套餐", planType: nil, primary: window("five_hour", 300), secondary: window("seven_day", 10080), credits: nil, nameKey:"Claude 官方套餐")
        if !main.windows.isEmpty { buckets["claude"] = main }
        for (key, title) in [("seven_day_sonnet", "Sonnet 周额度"), ("seven_day_opus", "Opus 周额度")] {
            if let value = window(key, 10080) { buckets[key] = QuotaBucket(limitId: key, limitName: title, planType: nil, primary: value, secondary: nil, credits: nil, nameKey:title) }
        }
        // 新版接口将 Fable 周额度放在 limits 中；percent 已按 Fable 自身上限计算。
        for row in object["limits"] as? [[String: Any]] ?? [] {
            guard row["kind"] as? String == "weekly_scoped",
                  let scope = row["scope"] as? [String: Any],
                  scope["surface"] == nil || scope["surface"] is NSNull,
                  let model = scope["model"] as? [String: Any],
                  let name = model["display_name"] as? String,
                  name.caseInsensitiveCompare("Fable") == .orderedSame else { continue }
            let key = "weekly_scoped_fable", title = "Fable 周额度"
            let value = QuotaWindow(usedPercent: number(row["percent"]), windowDurationMins: 10080, resetsAt: timestamp(row["resets_at"]))
            buckets[key] = QuotaBucket(limitId: key, limitName: title, planType: nil, primary: value, secondary: nil, credits: nil, nameKey: title)
        }
        guard buckets.values.contains(where:{ $0.remaining != nil }) else { throw ProviderPayloadError(message: "Claude 未提供可用额度；请确认官方订阅及登录权限") }
        return QuotaSnapshot(rateLimits: nil, rateLimitsByLimitId: buckets)
    }
    static func antigravity(_ data: Data) throws -> QuotaSnapshot {
        let object = try object(data)
        guard object["status"] as? String == "SUCCESS", let command = object["command"] as? [String: Any], command["name"] as? String == "usage", let body = command["data"] as? [String: Any], let groups = body["groups"] as? [[String: Any]] else { throw ProviderPayloadError(message: "Antigravity 额度查询失败；请在 agy 中确认登录和网络") }
        var buckets: [String: QuotaBucket] = [:]
        for (index, group) in groups.enumerated() {
            let name = group["name"] as? String ?? "额度组 \(index + 1)"
            var weekly: QuotaWindow?, session: QuotaWindow?
            for row in group["buckets"] as? [[String: Any]] ?? [] {
                guard row["disabled"] as? Bool != true else { continue }
                let kind = row["window"] as? String
                guard kind == "weekly" || kind == "5h" else { continue }
                let fraction = number(row["remaining_fraction"]).flatMap { (0...1).contains($0) ? $0 : nil }
                let window = QuotaWindow(usedPercent: fraction.map { 100 - $0 * 100 }, windowDurationMins: kind == "weekly" ? 10080 : 300, resetsAt: timestamp(row["reset_time"]))
                func stricter(_ current: QuotaWindow?, _ candidate: QuotaWindow) -> QuotaWindow {
                    guard let current else { return candidate }
                    switch (current.remaining, candidate.remaining) {
                    case (.some(let a), .some(let b)): return b < a ? candidate : current
                    case (.none, .some): return candidate
                    default: return current
                    }
                }
                if kind == "weekly" { weekly = stricter(weekly, window) } else { session = stricter(session, window) }
            }
            if weekly != nil || session != nil {
                let key = "group-\(index)"
                buckets[key] = QuotaBucket(limitId: key, limitName: name, planType: nil, primary: weekly, secondary: session, credits: nil, nameKey:group["name"] == nil ? "额度组 %@" : nil, nameArguments:[String(index + 1)])
            }
        }
        guard buckets.values.contains(where:{ $0.remaining != nil }) else { throw ProviderPayloadError(message: "Antigravity 未返回可用额度窗口") }
        return QuotaSnapshot(rateLimits: nil, rateLimitsByLimitId: buckets)
    }
    /// 抑制 Antigravity 服务端同一重置周期内的轻微回弹抖动（如多副本同步延迟或 ±1% 估算噪声）。
    static func stabilizeAntigravity(previous: QuotaSnapshot?, incoming: QuotaSnapshot, maxJitterPercent: Double = 2.5) -> QuotaSnapshot {
        guard let previous, let incomingMap = incoming.rateLimitsByLimitId else { return incoming }
        let previousBuckets = previous.buckets
        func matchBucket(_ bucket: QuotaBucket) -> QuotaBucket? {
            if let name = bucket.limitName {
                return previousBuckets.first { $0.limitName == name }
            }
            if let id = bucket.limitId {
                return previousBuckets.first { $0.limitId == id }
            }
            return nil
        }
        func stabilizeWindow(_ prev: QuotaWindow?, _ next: QuotaWindow?) -> QuotaWindow? {
            guard let next else { return nil }
            guard let prev,
                  let prevRem = prev.remaining, let nextRem = next.remaining,
                  let prevReset = prev.resetsAt, let nextReset = next.resetsAt,
                  prevReset > 0, nextReset > 0,
                  abs(prevReset - nextReset) <= 60,
                  prev.windowDurationMins == next.windowDurationMins else {
                return next
            }
            let rebound = nextRem - prevRem
            if rebound > 0 && rebound <= maxJitterPercent {
                return QuotaWindow(usedPercent: prev.usedPercent, windowDurationMins: next.windowDurationMins, resetsAt: next.resetsAt, periodLabel: next.periodLabel, localizesPeriodLabel: next.localizesPeriodLabel, expiresAt: next.expiresAt)
            }
            return next
        }
        var stabilized: [String: QuotaBucket] = [:]
        for (key, bucket) in incomingMap {
            guard let prev = matchBucket(bucket) else { stabilized[key] = bucket; continue }
            let primary = stabilizeWindow(prev.primary, bucket.primary)
            let secondary = stabilizeWindow(prev.secondary, bucket.secondary)
            stabilized[key] = QuotaBucket(limitId: bucket.limitId, limitName: bucket.limitName, planType: bucket.planType, primary: primary, secondary: secondary, credits: bucket.credits, nameKey: bucket.nameKey, nameArguments: bucket.nameArguments)
        }
        var result = QuotaSnapshot(rateLimits: incoming.rateLimits, rateLimitsByLimitId: stabilized)
        result.loginSource = incoming.loginSource
        return result
    }
}
