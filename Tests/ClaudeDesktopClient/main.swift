import Foundation
useTestLanguage()
func check(_ value: Bool, _ message: String) { if !value { fatalError(message) }; print("PASS " + message) }
final class DesktopResponse: URLProtocol {
    static var requests: [(String,String)] = []
    static var cliAccount = desktopAccountA
    static var cliOrg = desktopOrg
    static var desktopUsageStatus = 200
    static var profileCallback: (() -> Void)?
    static var usageCallback: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let token = request.value(forHTTPHeaderField:"Authorization")!.replacingOccurrences(of:"Bearer ",with:"")
        let path = request.url!.path
        check(request.url!.host == "api.anthropic.com","credentials only sent to fixed official host")
        Self.requests.append((token,path))
        let account = token == "cli-test" ? Self.cliAccount : token == "desktop-b" ? desktopAccountB : desktopAccountA
        let org = token == "cli-test" ? Self.cliOrg : token == "desktop-org-b" ? "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" : desktopOrg
        let status = path.hasSuffix("usage") && token.hasPrefix("desktop") ? Self.desktopUsageStatus : 200
        let body: [String:Any] = path.hasSuffix("profile") ? ["account":["uuid":account],"organization":["uuid":org]] : ["five_hour":["utilization":18],"seven_day":["utilization":39]]
        if path.hasSuffix("profile") { Self.profileCallback?() } else { Self.usageCallback?() }
        let response = HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:status == 429 ? ["Retry-After":"600"] : [:])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:try! JSONSerialization.data(withJSONObject:body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static func reset() { requests=[]; cliAccount=desktopAccountA; cliOrg=desktopOrg; desktopUsageStatus=200; profileCallback=nil;usageCallback=nil }
}
func query(_ client: ClaudeQuotaClient, changed: @escaping () -> Void = {}) -> Result<QuotaSnapshot,Error> {
    let done=DispatchSemaphore(value:0);var result:Result<QuotaSnapshot,Error>?
    client.fetch(allowPrompt:false,onAccountChange:changed) { result=$0;done.signal() }
    check(done.wait(timeout:.now()+4) == .success,"source query completes")
    return result!
}
func failed(_ result:Result<QuotaSnapshot,Error>)->Bool { if case .failure=result { return true };return false }
let home=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at:home,withIntermediateDirectories:true)
defer { try? FileManager.default.removeItem(at:home) }
var now=Date(timeIntervalSince1970:2_000_000_000),cliReads=0
func prepare(_ account:String=desktopAccountA,expired:Bool=false) throws {
    try writeDesktopConfig(home,account:account,entries:[desktopCacheKey(account:account):["token":account==desktopAccountA ? "desktop-a":"desktop-b","expiresAt":now.addingTimeInterval(expired ? -1:600).timeIntervalSince1970*1000]])
}
let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[DesktopResponse.self]
func client()->ClaudeQuotaClient {
    ClaudeQuotaClient(configuration:config,now:{ now },tokenProvider:{ _ in cliReads+=1;return "cli-test" },desktopCredentials:testDesktopStore(home,now:{ now }))
}
try prepare();DesktopResponse.reset();var primary=client()
let first=try query(primary).get()
check(DesktopResponse.requests.allSatisfy { $0.0=="desktop-a" } && cliReads==0,"desktop credentials are primary even when CLI is signed in")
check(first.loginSource=="Claude 桌面端","primary source is visible")
_ = try query(primary).get()
check(DesktopResponse.requests.filter { $0.1.hasSuffix("profile") }.count==1,"profile identity cached only for the same credential")
try prepare(desktopAccountB);var changes=0
_ = try query(primary,changed:{ changes+=1 }).get()
check(changes==1 && DesktopResponse.requests.last!.0=="desktop-b","account switch clears old readings and follows desktop")
primary.shutdown()

try prepare(expired:true);DesktopResponse.reset();cliReads=0
let backup=client();let saved=try query(backup).get()
check(cliReads==1 && saved.loginSource=="Claude Code 同账号备用","expired desktop login can use verified CLI backup")
check(DesktopResponse.requests.first!.1.hasSuffix("profile"),"backup verifies identity before reading quota")
backup.shutdown()
for mismatch in ["account","organization"] {
    DesktopResponse.reset();if mismatch=="account" { DesktopResponse.cliAccount=desktopAccountB } else { DesktopResponse.cliOrg="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" }
    let client=client();check(failed(query(client)),"different account or organization cannot become backup")
    check(DesktopResponse.requests.allSatisfy { !$0.1.hasSuffix("usage") },"mismatched backup never queries quota")
    client.shutdown()
}
try prepare();DesktopResponse.reset();DesktopResponse.desktopUsageStatus=401;cliReads=0
let unauthorized=client();check(try query(unauthorized).get().loginSource=="Claude Code 同账号备用","desktop authorization rejection uses same-account backup")
unauthorized.shutdown()
DesktopResponse.reset();DesktopResponse.desktopUsageStatus=429;cliReads=0
let limited=client();check(failed(query(limited)) && cliReads==0,"rate limit never triggers credential rotation")
let count=DesktopResponse.requests.count
try prepare(desktopAccountB);changes=0
check(failed(query(limited,changed:{ changes+=1 })) && changes==1,"account switch during cooldown clears previous account display")
check(DesktopResponse.requests.count==count,"account switch does not bypass rate limit")
limited.shutdown()
try prepare();DesktopResponse.reset()
DesktopResponse.profileCallback={ try! prepare(desktopAccountB) }
let changing=client();changes=0
check(failed(query(changing,changed:{ changes+=1 })) && changes>0,"desktop account changed in flight rejects old result")
check(DesktopResponse.requests.allSatisfy { !$0.1.hasSuffix("usage") },"stale identity does not start a quota request")
changing.shutdown()
try prepare();DesktopResponse.reset();DesktopResponse.desktopUsageStatus=429
DesktopResponse.usageCallback={ try! prepare(desktopAccountB) }
let raced=client();check(failed(query(raced)),"in-flight account switch does not consume old rate-limit result")
let requestsBefore=DesktopResponse.requests.count
DesktopResponse.usageCallback=nil
check(failed(query(raced)) && DesktopResponse.requests.count==requestsBefore,"in-flight 429 keeps shared cooldown after account switch")
raced.shutdown()
let otherOrg="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
func prepareOrganizations() throws {
    try writeDesktopConfig(home,entries:[desktopCacheKey():["token":"desktop-a","expiresAt":now.addingTimeInterval(600).timeIntervalSince1970*1000],desktopCacheKey(org:otherOrg):["token":"desktop-org-b","expiresAt":now.addingTimeInterval(600).timeIntervalSince1970*1000]])
    try selectDesktopOrganization(home,desktopOrg)
}
try prepareOrganizations();DesktopResponse.reset()
DesktopResponse.usageCallback={ try! selectDesktopOrganization(home,otherOrg) }
let orgRace=client();changes=0
check(failed(query(orgRace,changed:{ changes+=1 })) && changes>0,"same-account organization change rejects old in-flight reading")
orgRace.shutdown()
try prepareOrganizations();DesktopResponse.reset();DesktopResponse.desktopUsageStatus=429
let orgLimited=client();check(failed(query(orgLimited)),"organization cooldown established")
let orgRequests=DesktopResponse.requests.count
try selectDesktopOrganization(home,otherOrg);changes=0
check(failed(query(orgLimited,changed:{ changes+=1 })) && changes==1,"organization change clears cached reading during cooldown")
check(DesktopResponse.requests.count==orgRequests,"organization selection cannot bypass cooldown")
orgLimited.shutdown()
print("Desktop priority and same-account CLI backup verified")
