import Foundation
useTestLanguage()
func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
func rejects(_ action: () throws -> Void) { do { try action(); fatalError("invalid Harness data accepted") } catch {} }
let data = Data(#"{"code":0,"data":{"biz_code":0,"biz_data":{"normal_wallets":[{"currency":"CNY","balance":"12.34"},{"currency":"USD","balance":"0"}],"bonus_wallets":[{"currency":"CNY","balance":"3.21"}]}}}"#.utf8)
let balance = try HarnessBalance.decode(data)
check(balance.normal.first?.total == Decimal(string:"12.34"), "normal balance must not include the separate bonus")
check(balance.bonus.first?.total == Decimal(string:"3.21"), "bonus stays independent")
check(balance.normal.last?.total == 0, "reported zero is valid")
for raw in [#"{"code":1,"data":{"biz_code":0,"biz_data":{}}}"#, #"{"code":0,"data":{"biz_code":1,"biz_data":{}}}"#, #"{"code":0,"data":{"biz_code":0,"biz_data":{"normal_wallets":[{"currency":"CNY","balance":true}],"bonus_wallets":[]}}}"#] {
    rejects { _ = try HarnessBalance.decode(Data(raw.utf8)) }
}
let empty = try HarnessBalance.decode(Data(#"{"code":0,"data":{"biz_code":0,"biz_data":{"normal_wallets":[],"bonus_wallets":[]}}}"#.utf8))
check(empty.normal.isEmpty && empty.bonus.isEmpty, "missing wallets do not invent zero")
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
defer { try? FileManager.default.removeItem(at:directory) }
let file = directory.appendingPathComponent("credentials.yaml")
func credential(_ issuer: String = "https://platform.deepseek.com", version: Int = 1) -> String {
    "version: \(version)\nrecords:\n  deepseek-account-platform/default:\n    kind: grant\n    payload:\n      version: 1\n      token: 'synthetic: token # with YAML characters'\n      issuer: \(issuer)\n"
}
try Data(credential().utf8).write(to:file)
let token = try HarnessBalanceClient.credential(at:file)
check(token == "synthetic: token # with YAML characters", "safe YAML parsing preserves quoted credentials")
for raw in [credential("https://untrusted.example"),credential(version:2),"version: 1\nrecords: !ruby/object:Object {}\n","version: 1\nrecords: &a {x: *a}\n"] {
    try Data(raw.utf8).write(to:file)
    rejects { _ = try HarnessBalanceClient.credential(at:file) }
}
let request = try HarnessBalanceClient.request(token:"synthetic-session")
check(request.url?.absoluteString == "https://platform.deepseek.com/api/v0/users/get_user_summary" && request.httpMethod == "GET" && request.httpBody == nil, "only a read-only official balance endpoint is used")
check(request.value(forHTTPHeaderField:"x-dsh-auth-token") == "synthetic-session", "Harness session header differs from API bearer token")
rejects { _ = try HarnessBalanceClient.request(token:"bad\r\nheader") }
let domain = "local.quotanest.harness-test." + UUID().uuidString
let defaults = UserDefaults(suiteName:domain)!
defer { defaults.removePersistentDomain(forName:domain) }
let selection = DisplaySelection(defaults:defaults)
selection.select(.harness)
check(DisplaySelection(defaults:defaults).source == .harness, "Harness selection survives restart")
selection.select(.api("synthetic-api"))
check(DisplaySelection(defaults:defaults).source == .api("synthetic-api"), "API source is independent")
selection.select(.official(.zcode))
check(DisplaySelection(defaults:defaults).source == .official(.zcode), "ZCode can replace Harness selection")
defaults.removeObject(forKey:"selectedHarness")
defaults.set("qoder",forKey:"selectedProvider")
check(DisplaySelection(defaults:defaults).source == .official(.codex), "removed provider selection falls back to Codex")
print("Harness balance parsing, credential safety, fixed request and independent source selection passed")
