import Foundation
let domain = "local.quotanest.localization-tests." + UUID().uuidString
let defaults = UserDefaults(suiteName:domain)!
defer { defaults.removePersistentDomain(forName:domain) }
let resources = Bundle(path:".build/localizations.bundle")!
var system = ["zh-Hant-TW", "en-US"]
Localization.shared = Localization(defaults:defaults,resources:resources,systemLanguages:{ system })
assert(Localization.shared.language == "zh-Hans")
system = ["fr-FR", "zh-Hans"]
assert(Localization.shared.language == "en")
Localization.shared.preference = .chinese
assert(Localization(defaults:defaults,resources:resources,systemLanguages:{ ["en"] }).language == "zh-Hans")
assert(defaults.persistentDomain(forName:domain)?["AppleLanguages"] == nil)
assert(L("账户") == "账户")
let error = DeepSeekQueryError(message:"DeepSeek 凭据失效；请在 CC Switch 检查")
var reading = ConnectedAccountReading()
_ = reading.complete(.failure(error),generation:reading.begin()!)
assert(reading.error!.contains("凭据失效"))
Localization.shared.preference = .english
assert(L("账户") == "Accounts")
assert(L("剩余 %@", "42.0%") == "42.0% remaining")
assert(reading.error == "DeepSeek credentials expired; check CC Switch")
let window = QuotaWindow(usedPercent:12,windowDurationMins:300,resetsAt:nil)
assert(window.title == "5-hour quota")
print("PASS system routing, explicit preference, persistence, static/dynamic strings, cached errors")
Localization.shared.preference = .chinese
let wrapped = DeepSeekQueryError(message:"",sourceChanged:false,underlying:ConnectedAccountError(message:"CC Switch 正在更新配置；下次自动检查",isTransient:true))
var wrappedReading = ConnectedAccountReading()
_ = wrappedReading.complete(.failure(wrapped),generation:wrappedReading.begin()!)
var providerReading = ProviderReading()
providerReading.failure = UpdateError("GitHub 更新请求失败（%@）",arguments:["503"])
let status = UpdateInstallStatus(state:"installed",message:"已更新到 v%@",arguments:["1.8.0"])
assert(status.localizedMessage == "已更新到 v1.8.0")
let encodedStatus = try JSONEncoder().encode(status)
Localization.shared.preference = .english
assert(wrappedReading.error == "CC Switch is updating configuration; checking again automatically")
assert(providerReading.error == "GitHub update request failed (503)")
assert(UpdateMenuState.failed(providerReading.failure!).title == "GitHub update request failed (503)")
let decodedStatus = try JSONDecoder().decode(UpdateInstallStatus.self,from:encodedStatus)
assert(decodedStatus.localizedMessage == "Updated to v1.8.0")
let external = QuotaBucket(limitId:"wire",limitName:"Claude 官方套餐",planType:"账户",primary:nil,secondary:nil,credits:nil)
assert(external.displayName == "Claude 官方套餐", "external provider labels are never localization keys")
assert(QuotaWindow(usedPercent:10,windowDurationMins:nil,resetsAt:nil,periodLabel:"月度额度").title == "月度额度")
let generated = QuotaBucket(limitId:"owned",limitName:"Claude 官方套餐",planType:nil,primary:nil,secondary:nil,credits:nil,nameKey:"Claude 官方套餐")
assert(generated.displayName == "Claude official subscription")
let missingStore = CCSwitchStore(directory:URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString))
let client = DeepSeekBalanceClient(store:missingStore)
let done = DispatchSemaphore(value:0)
var captured: Error?
client.fetch(connectionID:"claude|none") { result in if case .failure(let failure) = result { captured = failure }; done.signal() }
assert(done.wait(timeout:.now()+3) == .success)
client.shutdown()
assert(captured!.localizedDescription == "CC Switch database not found; configure a service in CC Switch first")
Localization.shared.preference = .chinese
assert(captured!.localizedDescription == "未找到 CC Switch 数据库；请先在 CC Switch 配置服务")
print("PASS wrapped source errors, provider/update cached errors, persisted helper status, and external protocol label isolation")

Localization.shared.preference = .english
assert(L(" · 每 2 分钟检查") == " · checked every 2 minutes")
assert(L("更新：%@\n每 2 分钟刷新 · %@","12:00","UTC").contains("Refreshes every 2 minutes"))
assert(L("Claude 查询受限；将在 %@ 后重试","12:10:00") == "Claude usage is rate limited; retry after 12:10:00")
Localization.shared.preference = .chinese
assert(L("Claude 查询受限；将在 %@ 后重试","12:10:00").contains("12:10:00"))
print("PASS two-minute refresh and Claude cooldown translations")
