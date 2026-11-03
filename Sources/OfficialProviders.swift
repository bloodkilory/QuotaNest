import Foundation
import Security
import LocalAuthentication
import CryptoKit
final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
private struct ClaudeUsageHTTPError: LocalizedError {
    let code: Int
    var errorDescription: String? {
        if code == 401 { return L("Claude 登录失效；请打开 Claude Code 重新登录") }
        if code == 403 { return L("Claude 登录缺少额度读取权限；请用官方订阅账号重新登录") }
        return L("Claude 额度接口返回错误（%@）",String(code))
    }
}
final class ClaudeQuotaClient {
    private let queue = DispatchQueue(label: "local.codexquota.claude")
    private let redirectPolicy = NoRedirects()
    private let configuration: URLSessionConfiguration
    private let now: () -> Date
    private let tokenProvider: ((Bool) throws -> String)?
    private let desktopCredentials: ClaudeDesktopCredentials
    private var accountObserved = false
    private var expectsDesktop = false
    private var lastSelectionHint: String?
    private var lastTarget: String?
    private var verifiedTokens: [String:Data] = [:]
    private var nextRetry: Date?
    private var fallbackWait: TimeInterval = 120
    init(configuration: URLSessionConfiguration = .ephemeral, now: @escaping () -> Date = Date.init, tokenProvider: ((Bool) throws -> String)? = nil, desktopCredentials: ClaudeDesktopCredentials = ClaudeDesktopCredentials()) {
        self.configuration = configuration; self.now = now; self.tokenProvider = tokenProvider; self.desktopCredentials = desktopCredentials
    }
    private lazy var session: URLSession = {
        configuration.timeoutIntervalForRequest = 25; configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false; configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: redirectPolicy, delegateQueue: nil)
    }()
    private func credentials(allowPrompt: Bool) throws -> String {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        var data: Data?
        if FileManager.default.fileExists(atPath: file.path) { data = try Data(contentsOf: file) }
        if data == nil {
            let context = LAContext(); context.interactionNotAllowed = !allowPrompt
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Claude Code-credentials", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne, kSecUseAuthenticationContext as String: context]
            var value: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &value)
            guard status == errSecSuccess, let payload = value as? Data else {
                if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled { throw QuotaError(message: "钥匙串尚未授权；点击“授权 Claude 登录读取”后重试") }
                throw QuotaError(message: "未找到 Claude 官方登录；请运行 claude auth login")
            }
            data = payload
        }
        guard let data, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let oauth = root["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String, !token.isEmpty else { throw QuotaError(message: "没有可用的 Claude 订阅 OAuth 凭证；请运行 claude auth login") }
        if let expiry = oauth["expiresAt"] as? Double, expiry / 1000 <= Date().timeIntervalSince1970 { throw QuotaError(message: "Claude 登录已过期；请打开 Claude Code 更新登录后刷新") }
        return token
    }
    private func limitedError() -> QuotaError {
        let formatter = DateFormatter(); formatter.timeStyle = .medium
        return QuotaError(message:"Claude 查询受限；将在 %@ 后重试",arguments:[formatter.string(from:nextRetry!)])
    }
    private func rateLimitDelay(_ response: HTTPURLResponse) -> TimeInterval {
        let value = (response.value(forHTTPHeaderField:"Retry-After") ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        if let seconds = Double(value), seconds.isFinite, seconds > 0 { return max(120,seconds) }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT:0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        if let date = formatter.date(from:value), date > now() { return max(120,date.timeIntervalSince(now())) }
        return fallbackWait
    }
    private func stillCurrent(_ context: ClaudeDesktopContext?, changed: @escaping () -> Void) -> Bool {
        let hint = desktopCredentials.selectionHint()
        guard hint == context?.target else {
            lastTarget = nil; verifiedTokens.removeAll(); lastSelectionHint = hint
            expectsDesktop = expectsDesktop || hint != nil; changed(); return false
        }
        return true
    }
    private func request(_ endpoint: String, token: String, context: ClaudeDesktopContext?, deadline: TimeInterval, changed: @escaping () -> Void, completion: @escaping (Result<Data,Error>) -> Void) {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { completion(.failure(QuotaError(message:"Claude 查询超时；稍后自动刷新"))); return }
        var request = URLRequest(url:URL(string:"https://api.anthropic.com/api/oauth/" + endpoint)!)
        request.timeoutInterval = min(remaining,endpoint == "profile" ? 8 : 25)
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        request.setValue("oauth-2025-04-20",forHTTPHeaderField:"anthropic-beta")
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        session.dataTask(with:request) { data,response,error in
            self.queue.async {
                let limited = (response as? HTTPURLResponse)?.statusCode == 429
                if limited, let http = response as? HTTPURLResponse {
                    self.nextRetry = self.now().addingTimeInterval(self.rateLimitDelay(http))
                    self.fallbackWait = min(900,self.fallbackWait * 2)
                }
                guard self.stillCurrent(context,changed:changed) else { completion(.failure(QuotaError(message:"Claude 桌面端账号已改变；请刷新"))); return }
                if let error { completion(.failure(QuotaError(message:"Claude 网络查询失败（%@）",arguments:[String((error as NSError).code)]))); return }
                if limited { completion(.failure(self.limitedError())); return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data else { completion(.failure(ClaudeUsageHTTPError(code:(response as? HTTPURLResponse)?.statusCode ?? 0))); return }
                completion(.success(data))
            }
        }.resume()
    }
    private func load(_ token: String, source: String, context: ClaudeDesktopContext?, deadline: TimeInterval, changed: @escaping () -> Void, completion: @escaping (Result<QuotaSnapshot,Error>) -> Void) {
        let usage = {
            self.request("usage",token:token,context:context,deadline:deadline,changed:changed) { result in
                let parsed = result.flatMap { data in Result { () -> QuotaSnapshot in
                    var snapshot = try ProviderPayload.claude(data); snapshot.loginSource = source; return snapshot
                } }
                if case .success = parsed { self.nextRetry = nil; self.fallbackWait = 120 }
                completion(parsed)
            }
        }
        guard let context else { usage(); return }
        let digest = Data(SHA256.hash(data:Data(token.utf8)))
        if verifiedTokens[source] == digest { usage(); return }
        request("profile",token:token,context:context,deadline:deadline,changed:changed) { result in
            do {
                let data = try result.get()
                let profile = try JSONSerialization.jsonObject(with:data) as? [String:Any]
                let account = profile?["account"] as? [String:Any], organization = profile?["organization"] as? [String:Any]
                guard let accountID = account?["uuid"] as? String, let orgID = organization?["uuid"] as? String,
                      UUID(uuidString:accountID)?.uuidString.lowercased() == context.accountID, UUID(uuidString:orgID)?.uuidString.lowercased() == context.organizationID else {
                    throw QuotaError(message:"Claude 登录与桌面端不是同一账号或组织；未切换额度来源")
                }
                self.verifiedTokens[source] = digest; usage()
            } catch { completion(.failure(error)) }
        }
    }
    func fetch(allowPrompt: Bool = false, onAccountChange: @escaping () -> Void = {}, completion: @escaping (Result<QuotaSnapshot, Error>) -> Void) {
        queue.async {
            let account = self.desktopCredentials.accountHint()
            let hint = self.desktopCredentials.selectionHint()
            if self.accountObserved && hint != self.lastSelectionHint { self.lastTarget = nil; self.verifiedTokens.removeAll(); onAccountChange() }
            self.accountObserved = true; self.lastSelectionHint = hint; self.expectsDesktop = self.expectsDesktop || account != nil
            if let retry = self.nextRetry, retry > self.now() { completion(.failure(self.limitedError())); return }
            do {
                guard account != nil else {
                    if self.expectsDesktop { throw QuotaError(message:"未找到 Claude 桌面端登录；请先在桌面端登录") }
                    let token = try self.tokenProvider?(allowPrompt) ?? self.credentials(allowPrompt:allowPrompt)
                    self.load(token,source:"Claude Code",context:nil,deadline:ProcessInfo.processInfo.systemUptime+30,changed:onAccountChange,completion:completion); return
                }
                let desktop = try self.desktopCredentials.read(allowPrompt:allowPrompt)
                if let previous = self.lastTarget, previous != desktop.target { self.verifiedTokens.removeAll(); onAccountChange() }
                self.lastTarget = desktop.target
                self.lastSelectionHint = desktop.target
                let deadline = ProcessInfo.processInfo.systemUptime+30
                let backup = {
                    do {
                        let token = try self.tokenProvider?(allowPrompt) ?? self.credentials(allowPrompt:allowPrompt)
                        self.load(token,source:"Claude Code 同账号备用",context:desktop,deadline:deadline,changed:onAccountChange,completion:completion)
                    } catch { completion(.failure(error)) }
                }
                if let token = desktop.token {
                    self.load(token,source:"Claude 桌面端",context:desktop,deadline:deadline,changed:onAccountChange) { result in
                        if case .failure(let error) = result, let http = error as? ClaudeUsageHTTPError, [401,403].contains(http.code) { backup() }
                        else { completion(result) }
                    }
                } else { backup() }
            } catch { completion(.failure(error)) }
        }
    }
    func shutdown() { queue.sync { session.invalidateAndCancel() } }
}
final class AntigravityQuotaClient {
    private let queue = DispatchQueue(label: "local.codexquota.antigravity")
    private let runner = BoundedCommand()
    func fetch(_ completion: @escaping (Result<QuotaSnapshot, Error>) -> Void) {
        queue.async {
            completion(Result {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                guard let executable = [home + "/.local/bin/agy", "/opt/homebrew/bin/agy", "/usr/local/bin/agy"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw QuotaError(message: "未安装 Antigravity CLI；请安装并登录 agy") }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("codexquota-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                defer { try? FileManager.default.removeItem(at: directory) }
                for name in ["open", "xdg-open"] { try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent(name).path, withDestinationPath: "/usr/bin/false") }
                let allowed = Set(["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "LC_ALL", "HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "NO_PROXY", "https_proxy", "http_proxy", "all_proxy", "no_proxy"])
                var env = ProcessInfo.processInfo.environment.filter { allowed.contains($0.key) }
                env["PATH"] = directory.path + ":" + home + "/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                env["BROWSER"] = "/usr/bin/false"
                let versionData = try self.runner.run(executable, arguments: ["--version"], environment: env, timeout: 5)
                let parts = (String(data: versionData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").compactMap { Int($0) }
                guard parts.count == 3, parts[0] > 1 || (parts[0] == 1 && (parts[1] > 1 || (parts[1] == 1 && parts[2] >= 11))) else { throw QuotaError(message: "请将 Antigravity CLI 升级至 1.1.11 或更新版本") }
                // /usage is an official local command report, not a model prompt.
                // /usr/bin/env -C isolates the workspace without modifying HOME/login storage.
                let data = try self.runner.run("/usr/bin/env", arguments: ["-C", directory.path, executable, "-p", "/usage", "--output-format", "json"], environment: env)
                return try ProviderPayload.antigravity(data)
            })
        }
    }
    func shutdown() { runner.cancel(); queue.sync {} }
}
