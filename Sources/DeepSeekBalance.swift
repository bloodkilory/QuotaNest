import Foundation

struct DeepSeekWallet: Equatable {
    let currency: String
    let total: Decimal
    let granted: Decimal
    let toppedUp: Decimal
    static func amount(_ value: Decimal) -> String {
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX")
        formatter.numberStyle = .decimal; formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from:NSDecimalNumber(decimal:value)) ?? NSDecimalNumber(decimal:value).stringValue
    }
    var displayAmount: String { currency + " " + Self.amount(total) }
    var capsuleAmount: String {
        let value = NSDecimalNumber(decimal:total).doubleValue
        let prefix = currency == "CNY" ? "¥" : "$"
        if abs(value) >= 1_000_000_000 { return prefix + String(format:"%.0e",value).replacingOccurrences(of:"e+",with:"e") }
        if abs(value) >= 1_000_000 { return prefix + String(format:"%.1fM",value / 1_000_000) }
        if abs(value) >= 1_000 { return prefix + String(format:"%.1fk",value / 1_000) }
        return prefix + String(format:abs(value) < 1 ? "%.2f" : "%.1f",value)
    }
}
struct DeepSeekBalance: Equatable {
    let isAvailable: Bool
    let wallets: [DeepSeekWallet]
    static func decode(_ data: Data) throws -> Self {
        let error = ConnectedAccountError(message:"DeepSeek 未返回有效余额；不会将未知余额显示为零")
        guard data.count <= 1_048_576, let root = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let available = root["is_available"] as? Bool, let values = root["balance_infos"] as? [[String:Any]],
              !values.isEmpty, values.count <= 2 else { throw error }
        var currencies = Set<String>()
        let wallets = try values.map { value -> DeepSeekWallet in
            guard let currency = value["currency"] as? String, ["CNY","USD"].contains(currency), currencies.insert(currency).inserted else { throw error }
            func amount(_ key: String) throws -> Decimal {
                guard let text = value[key] as? String, text.count <= 38,
                      text.range(of:#"^-?[0-9]+(?:\.[0-9]+)?$"#,options:.regularExpression) != nil,
                      let number = Decimal(string:text,locale:Locale(identifier:"en_US_POSIX")), !number.isNaN else { throw error }
                return number
            }
            return try DeepSeekWallet(currency:currency,total:amount("total_balance"),granted:amount("granted_balance"),toppedUp:amount("topped_up_balance"))
        }
        return Self(isAvailable:available,wallets:wallets)
    }
}

struct HarnessBalance {
    let normal: [DeepSeekWallet]
    let bonus: [DeepSeekWallet]
}
struct HarnessReading {
    var balance: HarnessBalance?
    var lastSuccess: Date?
    var failure: Error?
    var refreshing = false
    var error: String? { failure?.localizedDescription }
}
