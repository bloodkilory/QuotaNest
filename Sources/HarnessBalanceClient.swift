import Foundation

/// Harness 官方界面将充值与赠送钱包分开显示，不合并为总余额。
extension HarnessBalance {
    static func decode(_ data: Data) throws -> Self {
        let root = try ChinaLoginPayload.object(data)
        if ChinaLoginPayload.number(root["code"]) == 40003 { throw DeepSeekQueryError(message:"DeepSeek Harness 登录已失效；请打开官方应用重新登录",sourceChanged:true) }
        guard ChinaLoginPayload.number(root["code"]) == 0, let envelope = root["data"] as? [String:Any],
              ChinaLoginPayload.number(envelope["biz_code"]) == 0, let body = envelope["biz_data"] as? [String:Any] else { throw ChinaLoginPayload.failure("DeepSeek Harness 未返回有效余额") }
        func wallets(_ key: String) throws -> [DeepSeekWallet] {
            guard let rows = body[key] as? [[String:Any]], rows.count <= 2 else { throw ChinaLoginPayload.failure("DeepSeek Harness 未返回有效余额") }
            var currencies = Set<String>()
            return try rows.map { row in
                guard let currency = row["currency"] as? String, ["CNY","USD"].contains(currency), currencies.insert(currency).inserted,
                      let text = row["balance"] as? String, text.count <= 38,
                      text.range(of:#"^-?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$"#,options:[.regularExpression,.caseInsensitive]) != nil,
                      let amount = Decimal(string:text,locale:Locale(identifier:"en_US_POSIX")), !amount.isNaN else { throw ChinaLoginPayload.failure("DeepSeek Harness 未返回有效余额") }
                return DeepSeekWallet(currency:currency,total:amount,granted:0,toppedUp:0)
            }
        }
        return try Self(normal:wallets("normal_wallets"),bonus:wallets("bonus_wallets"))
    }
}
/// 只读复用 Harness 登录；不刷新授权、不修改配置、不发起模型请求。
final class HarnessBalanceClient: ChinaSessionOwner {
    private let queue = DispatchQueue(label:"local.quotanest.harness")
    private let lock = NSLock()
    private var active: URLSession?
    private var stopped = false
    private var previousToken: String?
    func activate(_ session: URLSession) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if stopped { return false }
        active = session; return true
    }
    func deactivate(_ session: URLSession) { lock.lock(); defer { lock.unlock() }; if active === session { active = nil } }
    func shutdown() { lock.lock(); stopped = true; let session = active; lock.unlock(); session?.invalidateAndCancel() }
    private static var credentialFile: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configured = ProcessInfo.processInfo.environment["DSH_HOME"].flatMap { $0.isEmpty ? nil : $0 }
        return (configured.map { URL(fileURLWithPath:$0,isDirectory:true) } ?? home.appendingPathComponent(".dsh")).appendingPathComponent(".credentials.yaml")
    }
    static func credential(at file: URL) throws -> String {
        // 固定解析器直接读取文件，令牌不进入参数或环境变量。非普通文件和超限内容不读取。
        let script = #"""
        require 'json'
        require 'psych'
        begin
          file = File.open(ARGV.fetch(0), File::RDONLY | File::NONBLOCK)
          stat = file.stat
          exit 1 unless stat.file? && stat.size <= 1048576
          text = file.read(1048577)
          exit 1 unless text && text.bytesize <= 1048576
          root = Psych.safe_load(text, permitted_classes: [], permitted_symbols: [], aliases: false)
          exit 1 unless root.is_a?(Hash) && root['version'] == 1
          record = root.fetch('records', {}).fetch('deepseek-account-platform/default', {})
          exit 1 unless record['kind'] == 'grant'
          grant = record['payload']
          exit 1 unless grant.is_a?(Hash) && grant['version'] == 1 && grant['issuer'] == 'https://platform.deepseek.com'
          token = grant['token']
          exit 1 unless token.is_a?(String) && !token.empty? && token.bytesize <= 32768 && !token.match?(/[[:cntrl:]]/)
          STDOUT.write(JSON.generate(token))
        rescue Exception
          exit 1
        end
        """#
        do {
            let data = try BoundedCommand().run("/usr/bin/ruby",arguments:["-e",script,file.path],environment:["PATH":"/usr/bin:/bin","LANG":"en_US.UTF-8"],timeout:5)
            guard let token = try JSONSerialization.jsonObject(with:data,options:.fragmentsAllowed) as? String,
                  ChinaLoginPayload.header(token) != nil else { throw ChinaLoginPayload.failure("无法读取 DeepSeek Harness 登录；请打开官方应用重新登录") }
            return token
        } catch { throw DeepSeekQueryError(message:"无法读取 DeepSeek Harness 登录；请打开官方应用重新登录",sourceChanged:true) }
    }
    static func request(token: String) throws -> URLRequest {
        guard ChinaLoginPayload.header(token) != nil else { throw ChinaLoginPayload.failure("DeepSeek Harness 登录格式无效") }
        var request = URLRequest(url:URL(string:"https://platform.deepseek.com/api/v0/users/get_user_summary")!)
        request.httpMethod = "GET"
        request.setValue(token,forHTTPHeaderField:"x-dsh-auth-token")
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        return request
    }
    func fetch(onSourceChange: @escaping () -> Void = {}, completion: @escaping (Result<HarnessBalance,Error>) -> Void) {
        queue.async {
            completion(Result {
                let token = try Self.credential(at:Self.credentialFile)
                if self.previousToken != nil && self.previousToken != token { onSourceChange() }
                self.previousToken = token
                let result = Result {
                    try HarnessBalance.decode(ChinaQuotaTransport().run(Self.request(token:token),owner:self,unauthorizedError:DeepSeekQueryError(message:"DeepSeek Harness 登录已失效；请打开官方应用重新登录",sourceChanged:true)))
                }
                guard try Self.credential(at:Self.credentialFile) == token else { throw DeepSeekQueryError(message:"DeepSeek Harness 登录已变化；请刷新",sourceChanged:true) }
                return try result.get()
            })
        }
    }
}
