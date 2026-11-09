import AppKit
import Darwin
signal(SIGPIPE, SIG_IGN)
if CommandLine.arguments.contains("--check-connections") || CommandLine.arguments.contains("--check-deepseek") {
    do {
        let standard = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cc-switch")
        let directory = UserDefaults.standard.string(forKey:"ccSwitchDirectory").map { URL(fileURLWithPath:$0) } ?? standard
        let store = CCSwitchStore(directory:directory,liveDirectory:standard)
        let connections = try store.discover()
        if CommandLine.arguments.contains("--check-connections") {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            print(String(data:try encoder.encode(connections),encoding:.utf8)!); exit(0)
        }
        let selected: String? = CommandLine.arguments.firstIndex(of:"--connection-id").flatMap { $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil }
        let supported = connections.filter { $0.supportsBalance && (selected == nil || selected == $0.id) }
        guard !supported.isEmpty else { throw ConnectedAccountError(message:"没有匹配的 DeepSeek 官方连接；请在 CC Switch 检查") }
        let client = DeepSeekBalanceClient(store:store), group = DispatchGroup(), lock = NSLock()
        var success = true
        for connection in supported {
            group.enter()
            client.fetch(connectionID:connection.id) { result in
                lock.lock(); defer { lock.unlock(); group.leave() }
                switch result {
                case .success(let balance):
                    for wallet in balance.wallets { print("DeepSeek OK " + wallet.displayAmount + "; topped-up=" + DeepSeekWallet.amount(wallet.toppedUp) + "; granted=" + DeepSeekWallet.amount(wallet.granted)) }
                case .failure(let error): success = false; print(error.localizedDescription)
                }
            }
        }
        let complete = group.wait(timeout:.now()+35) == .success
        client.shutdown(); exit(complete && success ? 0 : 1)
    } catch { print(error.localizedDescription); exit(1) }
}
if CommandLine.arguments.contains("--check-harness") {
    let client = HarnessBalanceClient(), done = DispatchSemaphore(value:0)
    var success = false
    client.fetch { result in
        switch result {
        case .success(let balance):
            for wallet in balance.normal { print("DeepSeek Harness normal " + wallet.displayAmount) }
            for wallet in balance.bonus { print("DeepSeek Harness bonus " + wallet.displayAmount) }
            success = true
        case .failure(let error): print(error.localizedDescription)
        }
        done.signal()
    }
    let completed = done.wait(timeout:.now()+40) == .success
    client.shutdown(); exit(completed && success ? 0 : 1)
}
if CommandLine.arguments.contains("--check-all") {
    let group = DispatchGroup()
    let codex = CodexClient(), claude = ClaudeQuotaClient(), antigravity = AntigravityQuotaClient()
    let zcode = ZCodeQuotaClient()
    let report: (String, Result<QuotaSnapshot, Error>) -> Void = { name, result in
        switch result {
        case .success(let snapshot):
            let rows = snapshot.namedBuckets.map { name, bucket in
                name + ": " + (bucket.remaining.map { String(format: "%.1f%%", $0) } ?? "unknown")
            }.joined(separator: ", ")
            print(name + " OK " + rows)
        case .failure(let error): print(name + " UNAVAILABLE " + error.localizedDescription)
        }
        group.leave()
    }
    group.enter(); codex.fetch { report("Codex", $0) }
    group.enter(); claude.fetch { report("Claude", $0) }
    group.enter(); antigravity.fetch { report("Antigravity", $0) }
    group.enter(); zcode.fetch { report("ZCode", $0) }
    let completed = group.wait(timeout: .now() + 50) == .success
    codex.shutdown(); claude.shutdown(); antigravity.shutdown()
    zcode.shutdown()
    exit(completed ? 0 : 1)
}
if CommandLine.arguments.contains("--check") {
    let client = CodexClient()
    let done = DispatchSemaphore(value: 0)
    var ok = false
    client.fetch { result in
        switch result {
        case .success(let snapshot):
            print("Remaining: \(snapshot.remaining.map { String(format: "%.1f%%", $0) } ?? "unknown"); buckets: \(snapshot.buckets.count)"); ok = true
        case .failure(let error): print(error.localizedDescription)
        }
        client.stop(); done.signal()
    }
    _ = done.wait(timeout: .now() + 35)
    // Let queued process cleanup finish before exiting.
    Thread.sleep(forTimeInterval: 0.2)
    exit(ok ? 0 : 1)
}
let app = NSApplication.shared
let delegate = AppController()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
