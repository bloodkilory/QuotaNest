import Foundation

useTestLanguage()
func check(_ value: Bool, _ message: String) {
    if !value { fatalError(message) }
    print("PASS " + message)
}
final class UsageResponse: URLProtocol {
    static var status = 429
    static var headers: [String:String] = [:]
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        UsageResponse.requests += 1
        check(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage", "only official usage endpoint")
        check(request.value(forHTTPHeaderField:"Authorization") == "Bearer test-oauth", "official authorization header")
        let response = HTTPURLResponse(url:request.url!,statusCode:Self.status,httpVersion:nil,headerFields:Self.headers)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(#"{"five_hour":{"utilization":18},"seven_day":{"utilization":39}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
func query(_ client: ClaudeQuotaClient, prompt: Bool = false) -> Result<QuotaSnapshot,Error> {
    let done = DispatchSemaphore(value:0)
    var result: Result<QuotaSnapshot,Error>?
    client.fetch(allowPrompt:prompt) { result = $0; done.signal() }
    check(done.wait(timeout:.now()+3) == .success,"query completes without real network")
    return result!
}
func failed(_ result: Result<QuotaSnapshot,Error>) -> Bool {
    if case .failure = result { return true }; return false
}
func success(_ result: Result<QuotaSnapshot,Error>) -> Bool {
    if case .success(let snapshot) = result { return snapshot.rateLimitsByLimitId?["claude"]?.primary?.remaining == 82 }; return false
}
let emptyHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let noDesktop = ClaudeDesktopCredentials(home:emptyHome)
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [UsageResponse.self]
var time = Date(timeIntervalSince1970:2_000_000_000)
var credentialReads = 0
let client = ClaudeQuotaClient(configuration:config,now:{ time },tokenProvider:{ _ in credentialReads += 1; return "test-oauth" },desktopCredentials:noDesktop)
UsageResponse.headers = ["Retry-After":"600"]
check(failed(query(client)),"429 is reported")
time.addTimeInterval(120)
check(failed(query(client,prompt:true)),"manual refresh also respects cooldown")
check(UsageResponse.requests == 1 && credentialReads == 1,"cooldown makes no HTTP or credential request")
time.addTimeInterval(480)
UsageResponse.status = 200
check(success(query(client)),"query resumes at server deadline")
client.shutdown()

for header in [nil,"0","-1","invalid","Wed, 21 Oct 2015 07:28:00 GMT"] as [String?] {
    time = Date(timeIntervalSince1970:2_000_000_000)
    UsageResponse.requests = 0; UsageResponse.status = 429
    UsageResponse.headers = header.map { ["Retry-After":$0] } ?? [:]
    let client = ClaudeQuotaClient(configuration:config,now:{ time },tokenProvider:{ _ in "test-oauth" },desktopCredentials:noDesktop)
    for (index,delay) in [120.0,240,480,900,900].enumerated() {
        check(failed(query(client)),"repeated rate limit reported")
        let count = index+1
        check(UsageResponse.requests == count,"one request per permitted attempt")
        time.addTimeInterval(delay-1)
        check(failed(query(client,prompt:true)) && UsageResponse.requests == count,"backoff delays next request")
        time.addTimeInterval(1)
    }
    UsageResponse.status = 200
    check(success(query(client)),"successful response ends cooldown")
    UsageResponse.status = 429
    check(failed(query(client)),"new rate limit after success")
    let count = UsageResponse.requests
    time.addTimeInterval(120)
    UsageResponse.status = 200
    check(success(query(client)) && UsageResponse.requests == count+1,"success resets fallback wait to two minutes")
    client.shutdown()
}
time = Date(timeIntervalSince1970:2_000_000_000)
let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT:0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
UsageResponse.status = 429; UsageResponse.requests = 0
UsageResponse.headers = ["Retry-After":formatter.string(from:time.addingTimeInterval(600))]
let dated = ClaudeQuotaClient(configuration:config,now:{ time },tokenProvider:{ _ in "test-oauth" },desktopCredentials:noDesktop)
check(failed(query(dated)),"HTTP-date limit reported")
time.addTimeInterval(599)
check(failed(query(dated)) && UsageResponse.requests == 1,"HTTP-date respected")
time.addTimeInterval(1); UsageResponse.status = 200
check(success(query(dated)),"HTTP-date wait expires")
UsageResponse.status = 401
check(failed(query(dated)),"authentication error reported")
UsageResponse.status = 200
check(success(query(dated)),"authentication error does not create rate-limit cooldown")
dated.shutdown()
print("Claude rate-limit behavior verified")
