import Foundation
useTestLanguage()
func expect(_ condition: Bool, _ message: String) { if !condition { fatalError(message) }; print("PASS \(message)") }
let claude = try ProviderPayload.claude(Data(#"{"five_hour":{"utilization":12,"resets_at":"2026-10-12T20:00:00Z"},"seven_day":{"utilization":81,"resets_at":"2026-10-19T20:00:00Z"}}"#.utf8))
expect(claude.remaining == 19, "Claude utilization converted into remaining")
expect(claude.buckets[0].windows[0].resetsAt != nil, "Claude reset ISO date parsed")
// 按官方新版响应读取 Fable 自身的周额度，不用总周额度份额重新计算。
func fablePayload(_ percent: String, surface: String = "null") -> Data {
    Data("""
    {"five_hour":{"utilization":12},"seven_day":{"utilization":76},"limits":[{"kind":"weekly_scoped","group":"weekly","percent":\(percent),"severity":"normal","resets_at":"2026-10-30T10:00:00Z","scope":{"model":{"id":null,"display_name":"Fable"},"surface":\(surface)},"is_active":false}],"weekly_scoped_shares":[{"limit_index":0,"used_percent_of_weekly":33,"allowance_percent_of_weekly":50}]}
    """.utf8)
}
let fable = try ProviderPayload.claude(fablePayload("65"))
var selectedFable = ProviderReading(snapshot: fable)
expect(selectedFable.models.contains { $0.key == "weekly_scoped_fable" && $0.name == "Fable 周额度" }, "Fable is available as a separate quota model even when inactive")
selectedFable.modelID = "key:weekly_scoped_fable"
expect(selectedFable.window(for: .claude, period: .weekly)?.remaining == 35, "Fable uses its own percent instead of its share of the overall weekly quota")
expect(selectedFable.window(for: .claude, period: .weekly)?.resetsAt == 1793354400, "Fable reset belongs to its own quota")
expect(selectedFable.periods(for: .claude) == [.weekly], "Selected Fable has only its own weekly period")
for (percent, remaining) in [("0", 100.0), ("100", 0.0)] {
    let snapshot = try ProviderPayload.claude(fablePayload(percent))
    expect(snapshot.rateLimitsByLimitId?["weekly_scoped_fable"]?.remaining == remaining, "Fable preserves unused and exhausted quota")
}
selectedFable.snapshot = try ProviderPayload.claude(fablePayload("null"))
expect(selectedFable.selectedModel != nil && selectedFable.window(for: .claude, period: .weekly) == nil, "Unknown Fable never borrows the overall quota")
expect(claude.rateLimitsByLimitId?["weekly_scoped_fable"] == nil, "Legacy Claude responses do not invent Fable quota")
let surfaceFable = try ProviderPayload.claude(fablePayload("65", surface: #""cowork""#))
expect(surfaceFable.rateLimitsByLimitId?["weekly_scoped_fable"] == nil, "Surface-specific quota is not shown as overall Fable quota")
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

func agySnapshot(weekly: Double?, short: Double?, weeklyReset: String = "2026-12-03T07:02:56Z", shortReset: String = "2026-11-26T12:02:56Z", reordered: Bool = false) throws -> QuotaSnapshot {
    let w = weekly.map { String($0) } ?? "null"
    let s = short.map { String($0) } ?? "null"
    let gemini = #"{"name":"Gemini Models","buckets":[{"window":"weekly","remaining_fraction":\#(w),"reset_time":"\#(weeklyReset)"},{"window":"5h","remaining_fraction":\#(s),"reset_time":"\#(shortReset)"}]}"#
    let other = #"{"name":"Claude and GPT models","buckets":[{"window":"weekly","remaining_fraction":1,"reset_time":"1970-01-01T00:00:00Z"}]}"#
    let groups = reordered ? "[\(other),\(gemini)]" : "[\(gemini),\(other)]"
    return try ProviderPayload.antigravity(Data(#"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":\#(groups)}}}"#.utf8))
}
let agyBase = try agySnapshot(weekly: 0.9886, short: 0.9819)
let agyRebound = try agySnapshot(weekly: 0.9891, short: 0.9865, reordered: true)
let agyStabilized = ProviderPayload.stabilizeAntigravity(previous: agyBase, incoming: agyRebound)
expect(abs((ProviderReading(snapshot: agyStabilized).window(for: .antigravity, period: .weekly)?.remaining ?? 0) - 98.86) < 0.001, "Antigravity suppresses small same-cycle weekly rebound even when groups reorder")
expect(abs((ProviderReading(snapshot: agyStabilized).window(for: .antigravity, period: .short)?.remaining ?? 0) - 98.19) < 0.001, "Antigravity suppresses small same-cycle 5h rebound")
let agyDrop = try agySnapshot(weekly: 0.9784, short: 0.9708)
let agyDropped = ProviderPayload.stabilizeAntigravity(previous: agyStabilized, incoming: agyDrop)
expect(abs((ProviderReading(snapshot: agyDropped).window(for: .antigravity, period: .weekly)?.remaining ?? 0) - 97.84) < 0.001, "Antigravity immediately reflects real quota consumption")
let agyNewCycle = try agySnapshot(weekly: 1.0, short: 1.0, weeklyReset: "2026-12-10T07:02:56Z", shortReset: "2026-11-26T17:02:56Z")
let agyReset = ProviderPayload.stabilizeAntigravity(previous: agyDropped, incoming: agyNewCycle)
expect(ProviderReading(snapshot: agyReset).window(for: .antigravity, period: .weekly)?.remaining == 100, "Antigravity adopts full quota when reset cycle advances")
let agyLargeJump = try agySnapshot(weekly: 0.999, short: 0.999)
let agyJumped = ProviderPayload.stabilizeAntigravity(previous: try agySnapshot(weekly: 0.95, short: 0.95), incoming: agyLargeJump)
expect(abs((ProviderReading(snapshot: agyJumped).window(for: .antigravity, period: .weekly)?.remaining ?? 0) - 99.9) < 0.001, "Antigravity does not clamp genuine large quota increases")
