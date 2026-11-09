import Foundation
useTestLanguage()
func expect(_ condition: Bool, _ message: String) { if !condition { fatalError(message) }; print("PASS \(message)") }
let claude = try ProviderPayload.claude(Data(#"{"five_hour":{"utilization":12,"resets_at":"2026-10-12T20:00:00Z"},"seven_day":{"utilization":81,"resets_at":"2026-10-19T20:00:00Z"}}"#.utf8))
expect(claude.remaining == 19, "Claude utilization converted into remaining")
expect(claude.buckets[0].windows[0].resetsAt != nil, "Claude reset ISO date parsed")
let agy = try ProviderPayload.antigravity(Data(#"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"weekly","window":"weekly","remaining_fraction":0.31,"reset_time":"2026-10-14T03:25:48Z"},{"id":"5h","disabled":true,"remaining_fraction":0}]},{"name":"Claude and GPT models","buckets":[{"id":"weekly","window":"weekly","remaining_fraction":0}]}]}}}"#.utf8))
expect(agy.buckets.count == 2, "Antigravity keeps separate quota groups")
expect(agy.buckets[0].windows.count == 1, "Disabled Antigravity bucket excluded")
expect(agy.buckets[0].remaining == 31, "Antigravity fraction not treated as used")
expect(agy.buckets[1].remaining == 0, "Exhausted group remains visible")
for source in [#"{"status":"ERROR","command":{"name":"usage","data":{"groups":[]}}}"#, #"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini","buckets":[{"window":"weekly"}]}]}}}"#] {
    do { _ = try ProviderPayload.antigravity(Data(source.utf8)); fatalError("unknown quota accepted") } catch { print("PASS unknown/error quota rejected") }
}
do { _ = try ProviderPayload.claude(Data(#"{"five_hour":null}"#.utf8)); fatalError("missing Claude quota accepted") } catch { print("PASS missing Claude quota rejected") }

expect(ProviderReading(snapshot: agy).remaining(for: .antigravity) == 31, "Antigravity capsule selects Gemini despite exhausted other models")
func group(_ name: String, _ used: Double, _ secondary: Double? = nil) -> QuotaBucket {
    QuotaBucket(limitId: nil, limitName: name, planType: nil,
                primary: QuotaWindow(usedPercent: used, windowDurationMins: 10080, resetsAt: nil),
                secondary: secondary.map { QuotaWindow(usedPercent: $0, windowDurationMins: 300, resetsAt: nil) }, credits: nil)
}
let mixed = QuotaSnapshot(rateLimits: nil, rateLimitsByLimitId: ["first": group("Claude and GPT models", 100), "last": group("GEMINI Models", 20, 60), "middle": group("Gemini Pro", 30)])
expect(ProviderReading(snapshot: mixed).remaining(for: .antigravity) == 40, "Gemini matching ignores order and case and takes restrictive Gemini window")
let noGemini = QuotaSnapshot(rateLimits: nil, rateLimitsByLimitId: ["other": group("Claude and GPT models", 20)])
expect(ProviderReading(snapshot: noGemini).remaining(for: .antigravity) == nil, "Missing Gemini is unknown instead of another model quota")
expect(ProviderReading(snapshot: mixed).remaining(for: .claude) == 0, "Claude selection retains existing aggregation")

let split = ProviderReading(snapshot: mixed)
expect(split.window(for: .antigravity, period: .short)?.remaining == 40, "Short selection uses Gemini hours only")
expect(split.window(for: .antigravity, period: .weekly)?.remaining == 70, "Weekly selection excludes hour limits and other families")
expect(split.periodLabel(for: .antigravity, period: .short) == "5h", "Period label follows actual window duration")
expect(split.periods(for: .antigravity) == [.short, .weekly], "Two valid periods support switching")
let weeklyOnly = ProviderReading(snapshot: agy)
expect(weeklyOnly.period(for: .antigravity, preferred: .short) == .weekly, "Disabled hours fall back to available weekly period")
expect(weeklyOnly.periods(for: .antigravity) == [.weekly], "Disabled hour window is not switchable")
expect(ProviderReading(snapshot: noGemini).periods(for: .antigravity).isEmpty, "Other families cannot provide Gemini switch periods")

let monthly = QuotaWindow(usedPercent: 25, windowDurationMins: nil, resetsAt: nil, periodLabel: "月度额度")
let billing = QuotaBucket(limitId: "zcode", limitName: "ZCode", planType: nil, primary: monthly, secondary: nil, credits: nil)
let credits = ProviderReading(snapshot: QuotaSnapshot(rateLimits: billing, rateLimitsByLimitId: nil))
expect(credits.periods(for: .zcode) == [.billing], "Credits use billing period without an invented duration")
expect(credits.window(for: .zcode, period: .billing)?.remaining == 75, "Billing retains actual remaining quota")
expect(credits.periodLabel(for: .zcode, period: .billing) == "额", "Billing capsule has compact label")
expect(monthly.title == "月度额度", "Calendar-month title preserved")


var chosen = ProviderReading(snapshot:mixed)
chosen.modelID = chosen.models.first { $0.name == "Claude and GPT models" }!.id
expect(chosen.window(for:.antigravity,period:.weekly)?.remaining == 0,"explicit model overrides Gemini default without borrowing Gemini quota")
expect(chosen.period(for:.antigravity,preferred:.short) == .weekly,"model without short window falls back to its own weekly period")
chosen.modelID = chosen.models.first { $0.name == "Gemini Pro" }!.id
expect(chosen.window(for:.claude,period:.weekly)?.remaining == 70,"explicit model does not use another group's zero balance")
expect(chosen.periods(for:.claude) == [.weekly],"period choices belong only to selected model")
let chosenID = chosen.modelID
chosen.snapshot = QuotaSnapshot(rateLimits:nil,rateLimitsByLimitId:["reordered":group("Gemini Pro",30),"another":group("Claude and GPT models",100)])
expect(chosen.selectedModel?.id == chosenID && chosen.window(for:.claude,period:.weekly)?.remaining == 70,"model identity survives reordered indexed groups")
chosen.snapshot = noGemini
expect(chosen.selectedModel == nil && chosen.window(for:.claude,period:.weekly)?.remaining == 80,"removed model resolves to visible automatic default")
let unknownBucket = QuotaBucket(limitId:"unknown",limitName:"Unknown Model",planType:nil,primary:QuotaWindow(usedPercent:nil,windowDurationMins:10080,resetsAt:1000),secondary:nil,credits:nil)
chosen.snapshot = QuotaSnapshot(rateLimits:nil,rateLimitsByLimitId:["known":group("Known Model",20),"unknown":unknownBucket])
chosen.modelID = chosen.models.first { $0.name == "Unknown Model" }!.id
expect(chosen.selectedModel != nil && chosen.window(for:.claude,period:.weekly) == nil,"unknown selected model never borrows another model's percentage")
let duplicateNames = QuotaSnapshot(rateLimits:nil,rateLimitsByLimitId:["a":group("Same",10),"b":group("Same",20)])
expect(Set(ProviderReading(snapshot:duplicateNames).models.map { $0.id }).count == 2,"duplicate model titles retain distinct radio identities")

let partiallyUnknown = try ProviderPayload.claude(Data(#"{"five_hour":{"utilization":18},"seven_day_sonnet":{"utilization":null}}"#.utf8))
var unknownSonnet = ProviderReading(snapshot:partiallyUnknown)
expect(unknownSonnet.models.contains { $0.key == "seven_day_sonnet" },"Claude preserves a returned unknown model instead of deleting it")
unknownSonnet.modelID = unknownSonnet.models.first { $0.key == "seven_day_sonnet" }!.id
expect(unknownSonnet.window(for:.claude,period:.short) == nil && unknownSonnet.window(for:.claude,period:.weekly) == nil,"real parsed unknown Sonnet never falls back to valid Claude balance")

let unknownGroup = try ProviderPayload.antigravity(Data(#"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"window":"weekly","remaining_fraction":0.8}]},{"name":"Claude and GPT models","buckets":[{"window":"weekly","remaining_fraction":null}]}]}}}"#.utf8))
expect(unknownGroup.buckets.count == 2,"Antigravity preserves returned unknown model rather than borrowing Gemini")
var unknownAG = ProviderReading(snapshot:unknownGroup)
unknownAG.modelID = "name:Claude and GPT models"
expect(unknownAG.selectedModel != nil && unknownAG.window(for:.antigravity,period:.weekly) == nil,"parsed unknown non-Gemini model stays unknown")
