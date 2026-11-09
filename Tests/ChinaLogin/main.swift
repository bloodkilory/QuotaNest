import Foundation
import CryptoKit
import Darwin

useTestLanguage()
func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
func data(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
func rejects(_ action: () throws -> Void, _ message: String) { do { try action(); fatalError(message) } catch {} }
let zcode = try ChinaLoginPayload.zcode(data(["code": 200, "data": ["limits": [["type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 25], ["type": "CREDIT_LIMIT", "unit": 6, "percentage": 40], ["type": "TIME_LIMIT", "unit": 5, "number": 1, "percentage": 10]]]]))
check(zcode.rateLimitsByLimitId?["zcode"]?.primary?.remaining == 75, "ZCode percentage is used")
check(zcode.rateLimitsByLimitId?["zcode"]?.secondary?.minutes == 10080, "weekly units")
check(zcode.rateLimitsByLimitId?["zcode-tools"]?.primary?.minutes == nil, "calendar month must not invent 30 day duration")
check(zcode.rateLimitsByLimitId?["zcode-tools"]?.primary?.title == "月工具额度", "monthly label")
rejects({ _ = try ChinaLoginPayload.zcodeEnvelope(data(["code": 1e100, "data": [:]])) }, "huge numeric code rejected safely")
let secret = "fixture-only-secret"
let box = try AES.GCM.seal(Data("fixture-session".utf8), using: SymmetricKey(data: SHA256.hash(data: Data(secret.utf8))))
func b64(_ value: Data) -> String { value.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
let encrypted = "enc:v1:" + b64(Data(box.nonce)) + "." + b64(box.tag) + "." + b64(box.ciphertext)
let decrypted = try ChinaLoginPayload.decryptZCode(encrypted, home: "/fixture", username: "fixture", secret: secret)
check(decrypted == "fixture-session", "official AES-GCM format")
rejects({ _ = try ChinaLoginPayload.decryptZCode(encrypted, home: "/fixture", username: "fixture", secret: "wrong") }, "wrong secret must fail")
check(ChinaLoginPayload.header("secret\r\nInjected: yes") == nil, "header injection blocked")
let personalProject = try ChinaLoginPayload.zcodePersonalProject(["organizations": [["organizationId": "org", "projects": [["projectId": "team", "projectName": "默认项目", "projectType": " 2 "], ["projectId": "personal", "projectType": 1]]]]])
check(personalProject.projectID == "personal", "whitespace-wrapped team type must not be selected as personal")
rejects({ _ = try ChinaLoginPayload.zcodePersonalProject(["organizations": [["organizationId": "org", "projects": [["projectId": "team", "projectType": " 2 "]]]]]) }, "team-only account must not become personal")
let fileDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: fileDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: fileDirectory) }
let fifo = fileDirectory.appendingPathComponent("credentials.json")
check(mkfifo(fifo.path, 0o600) == 0, "synthetic FIFO fixture")
rejects({ _ = try readChinaCredentialFile(fifo, message: "fixture rejection") }, "credential FIFO must fail without blocking")
let transport = ChinaQuotaTransport()
let session = URLSession(configuration: .ephemeral)
let task = session.dataTask(with: URL(string: "https://bigmodel.cn/")!)
var redirectDenied = false
transport.urlSession(session, task: task, willPerformHTTPRedirection: HTTPURLResponse(url: URL(string: "https://bigmodel.cn/")!, statusCode: 302, httpVersion: nil, headerFields: nil)!, newRequest: URLRequest(url: URL(string: "https://example.invalid/")!)) { redirectDenied = $0 == nil }
check(redirectDenied, "credential-bearing redirects refused")
var oversizedDenied = false
transport.urlSession(session, dataTask: task, didReceive: URLResponse(url: URL(string: "https://bigmodel.cn/")!, mimeType: "application/json", expectedContentLength: 1_048_577, textEncodingName: "utf-8")) { oversizedDenied = $0 == .cancel }
check(oversizedDenied, "oversized response rejected before download")
session.invalidateAndCancel()


check(!ChinaLoginPayload.zcodeRequestAllowed(path: "/api/biz/v1/organization/org/projects/project/api_keys", hasBody: true, bearer: false), "persistent key creation forbidden")
check(!ChinaLoginPayload.zcodeRequestAllowed(path: "/api/biz/v1/organization/org/projects/project/api_keys", hasBody: true, bearer: true), "persistent key creation forbidden even with bearer")
check(ChinaLoginPayload.zcodeRequestAllowed(path: "/api/biz/v1/organization/org/projects/project/api_keys/id/access_tokens", hasBody: true, bearer: true), "existing-key scoped session exchange allowed")

let issuedFixture = data(["code": 200, "data": ["accessToken": "fixture-only", "tokenType": "Bearer", "expiresAt": 200, "expiresIn": 100]])
let issued = try ChinaLoginPayload.zcodeProjectToken(issuedFixture, now: 150)
check(issued == "fixture-only", "project token expiry uses seconds")
rejects({ _ = try ChinaLoginPayload.zcodeProjectToken(issuedFixture, now: 201) }, "expired project token rejected")
rejects({ _ = try ChinaLoginPayload.zcodeProjectToken(data(["code": 200, "data": ["enable": false]]), now: 150) }, "disabled exchange rejected")
print("China login fixture and transport contracts passed")

func startPlanFixture(_ balances: [[String:Any]]? = nil, planName: String = "Start Plan") -> Data {
    let entitlements: [[String:Any]] = [
        ["entitlement_id":"alpha","period":"daily","effective_at":900],
        ["entitlement_id":"beta","period":"daily","effective_at":900],
        ["entitlement_id":"unknown","period":"daily"],
        ["entitlement_id":"burst","period":"one_time"],
        ["entitlement_id":"future","period":"daily","effective_at":1400,"grant_units":9900]
    ]
    let plans: [[String:Any]] = [
        ["user_plan_id":"synthetic-user-plan","plan_id":"synthetic-plan","name":planName,"status":"active","starts_at":800,"ends_at":1800,"entitlements":entitlements],
        ["user_plan_id":"expired-user-plan","plan_id":"expired-plan","status":"active","ends_at":999,"entitlements":entitlements],
        ["user_plan_id":"future-user-plan","plan_id":"future-plan","status":"active","starts_at":1500,"entitlements":entitlements],
        ["user_plan_id":"inactive-user-plan","plan_id":"inactive-plan","status":"cancelled","entitlements":entitlements]
    ]
    let rows = balances ?? [
        ["bucket_id":"bucket-a","user_plan_id":"synthetic-user-plan","plan_id":"synthetic-plan","entitlement_id":"alpha","show_name":"Model Alpha","total_units":1200,"remaining_units":0,"period_start":900,"period_end":1100,"expires_at":1100],
        ["bucket_id":"bucket-b","user_plan_id":"synthetic-user-plan","plan_id":"synthetic-plan","entitlement_id":"beta","show_name":"Model Beta","total_units":800,"remaining_units":200,"period_start":900,"period_end":1150,"expires_at":1150],
        ["bucket_id":"bucket-u","user_plan_id":"synthetic-user-plan","plan_id":"synthetic-plan","entitlement_id":"unknown","show_name":"Model Unknown","total_units":200,"period_end":1200],
        ["bucket_id":"bucket-burst","user_plan_id":"synthetic-user-plan","plan_id":"synthetic-plan","entitlement_id":"burst","show_name":"Model Burst","total_units":100,"remaining_units":50,"period_end":1600,"expires_at":1700],
        ["bucket_id":"old","user_plan_id":"expired-user-plan","plan_id":"expired-plan","entitlement_id":"alpha","show_name":"Expired plan","total_units":50,"remaining_units":50],
        ["bucket_id":"later","user_plan_id":"future-user-plan","plan_id":"future-plan","entitlement_id":"alpha","show_name":"Future plan","total_units":50,"remaining_units":50],
        ["bucket_id":"inactive-row","user_plan_id":"inactive-user-plan","plan_id":"inactive-plan","entitlement_id":"alpha","show_name":"Inactive plan","total_units":50,"remaining_units":50],
        ["bucket_id":"old-row","user_plan_id":"synthetic-user-plan","plan_id":"synthetic-plan","entitlement_id":"alpha","show_name":"Expired row","total_units":50,"remaining_units":50,"expires_at":999],
        ["bucket_id":"later-row","user_plan_id":"synthetic-user-plan","plan_id":"synthetic-plan","entitlement_id":"future","show_name":"Future row","total_units":50,"remaining_units":50,"period_start":1500]
    ]
    return data(["code":0,"data":["server_time":1000,"plans":plans,"balances":rows]])
}
let startPlan: QuotaSnapshot
do { startPlan = try ChinaLoginPayload.zcode(startPlanFixture()) }
catch { fatalError("Start Plan balance payload must produce separate model quota buckets") }
check(startPlan.buckets.count == 4,"Start Plan filters expired and future plans/rows without fabricating grants")
func model(_ name: String) -> QuotaBucket { startPlan.buckets.first { $0.displayName == "Start Plan · " + name }! }
check(model("Model Alpha").primary?.remaining == 0,"real zero remains exhausted, not unknown")
check(model("Model Beta").primary?.remaining == 25,"Start Plan remaining/total units produce model-specific remaining percent")
check(model("Model Unknown").primary?.remaining == nil,"missing usage stays unknown, not exhausted")
check(model("Model Alpha").primary?.minutes == 1440 && model("Model Beta").primary?.resetsAt == 1150,"daily period and full reset seconds preserved")
check(model("Model Burst").primary?.minutes == nil && model("Model Burst").primary?.title == "一次性额度","one-time entitlement stays a labeled billing quota")
let startReading = ProviderReading(snapshot:startPlan)
check(startReading.period(for:.zcode,preferred:.short)?.rawValue == "daily","ZCode selects daily when no short window exists")
check(startReading.periodLabel(for:.zcode,period:startReading.period(for:.zcode,preferred:.short)) == "1d","daily capsule uses compact 1d label")
check(startReading.window(for:.zcode,period:startReading.period(for:.zcode,preferred:.short))?.remaining == 0,"daily model minimum retains real zero")
rejects({ _ = try ChinaLoginPayload.zcode(startPlanFixture([])) },"future grants and empty balances never fabricate quota")
print("ZCode Start Plan synthetic models, zero/unknown, plan expiry, future grants and daily/billing selection passed")
let startRequest = try ZCodeQuotaClient.startPlanRequest(token:"synthetic-session",deviceMid:"synthetic-mid",version:"8.4.2",platform:"darwin-arm64",language:"en-US",timezone:"Etc/UTC")
check(startRequest.url?.absoluteString == "https://zcode.z.ai/api/v1/zcode-plan/billing/balance?app_version=8.4.2","Start Plan only targets its fixed HTTPS balance endpoint")
check(startRequest.httpMethod == "GET" && startRequest.httpBody == nil,"Start Plan request cannot claim a plan or send a body")
for (name,value) in ["Authorization":"Bearer synthetic-session","X-Device-Mid":"synthetic-mid","X-Platform":"darwin-arm64","X-ZCode-App-Version":"8.4.2","User-Agent":"ZCode/8.4.2","HTTP-Referer":"https://zcode.z.ai","X-Title":"Z Code@electron","X-Os-Category":"macos","X-Client-Language":"en-US","X-Client-Timezone":"Etc/UTC"] {
    check(startRequest.value(forHTTPHeaderField:name) == value,"Start Plan official request header " + name)
}
rejects({ _ = try ZCodeQuotaClient.startPlanRequest(token:"fixture",deviceMid:"injected\nheader",version:"8.4.2",platform:"darwin-x64",language:"zh-CN",timezone:"Etc/UTC") },"invalid existing device information cannot enter headers")
for values: [String:Any] in [["total_units":0,"remaining_units":0],["total_units":200,"remaining_units":true],["total_units":200,"remaining_units":-1],["total_units":200,"remaining_units":300]] {
    var row: [String:Any] = ["user_plan_id":"synthetic-user-plan","plan_id":"synthetic-plan","entitlement_id":"alpha","show_name":"Unknown counters"]
    row.merge(values) { _,new in new }
    let parsed = try ChinaLoginPayload.zcode(startPlanFixture([row]))
    check(parsed.buckets[0].primary?.remaining == nil,"invalid/empty counters remain unknown rather than a fabricated percentage")
}
check(model("Model Burst").primary?.resetsAt == nil && model("Model Burst").primary?.expiresAt == 1700,"one-time expiry never becomes a daily reset")
for language in [InterfaceLanguage.chinese,.english] {
    useTestLanguage(language)
    check(model("Model Burst").primary?.title == (language == .english ? "One-time quota" : "一次性额度"),"one-time label is localized without translating model names")
}
print("ZCode Start Plan fixed GET, native headers and expiry semantics passed")

let seasonal = try ChinaLoginPayload.zcode(startPlanFixture(planName:"Seasonal Demo Pass"))
check(seasonal.buckets.allSatisfy { $0.displayName.hasPrefix("Seasonal Demo Pass · ") },"activity plan names distinguish model balances from the daily Start Plan")

let paidUnknownTool = try ChinaLoginPayload.zcode(data(["code":200,"data":["limits":[["type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":25],["type":"TIME_LIMIT","unit":5,"number":1,"percentage":NSNull()]]]]))
check(paidUnknownTool.rateLimitsByLimitId?["zcode-tools"]?.primary != nil,"returned unknown paid ZCode tool quota remains selectable")
var paidToolReading = ProviderReading(snapshot:paidUnknownTool); paidToolReading.modelID = "key:zcode-tools"
check(paidToolReading.selectedModel != nil && paidToolReading.window(for:.zcode,period:.billing)?.remaining == nil,"unknown selected tool quota never borrows paid coding quota")
rejects({ _ = try ChinaLoginPayload.zcode(data(["code":200,"data":["limits":[["type":"TIME_LIMIT","unit":5,"number":1,"percentage":NSNull()]]]])) },"all-unknown paid ZCode response retains query failure semantics")
