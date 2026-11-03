import Foundation
import Security
import LocalAuthentication
import CommonCrypto
import CryptoKit
import SQLite3

struct ClaudeDesktopContext {
    let accountID: String
    let organizationID: String
    let token: String?
    var target: String { accountID + "|" + organizationID }
}
final class ClaudeDesktopCredentials {
    private let home: URL
    private let now: () -> Date
    private let keyReader: ((Bool) throws -> Data)?
    private var cachedPassword: Data?
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, now: @escaping () -> Date = Date.init, keyReader: ((Bool) throws -> Data)? = nil) {
        self.home = home; self.now = now; self.keyReader = keyReader
    }
    private var directory: URL { home.appendingPathComponent("Library/Application Support/Claude") }
    private func config() throws -> [String:Any] {
        guard let root = try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("config.json"))) as? [String:Any] else { throw QuotaError(message:"Claude 桌面端登录记录无效；请在桌面端重新登录") }
        return root
    }
    func accountHint() -> String? {
        guard let value = try? config()["lastKnownAccountUuid"] as? String else { return nil }
        return UUID(uuidString:value)?.uuidString.lowercased()
    }
    private func password(allowPrompt: Bool) throws -> Data {
        if !allowPrompt, let cachedPassword { return cachedPassword }
        if let keyReader { return try keyReader(allowPrompt) }
        let context = LAContext(); context.interactionNotAllowed = !allowPrompt
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"Claude Safe Storage",kSecAttrAccount as String:"Claude Key",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne,kSecUseAuthenticationContext as String:context]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary,&value)
        guard status == errSecSuccess, let data = value as? Data else {
            throw QuotaError(message:"Claude 桌面端登录尚未授权读取；点击“授权 Claude 登录读取”后重试")
        }
        return data
    }
    private func decrypt(_ encrypted: Data, password: Data) throws -> Data {
        guard encrypted.count > 3, [Data("v10".utf8),Data("v11".utf8)].contains(encrypted.prefix(3)) else { throw QuotaError(message:"Claude 桌面端登录加密格式暂不支持") }
        var key = [UInt8](repeating:0,count:16)
        let salt = Array("saltysalt".utf8)
        let derived = password.withUnsafeBytes { bytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),bytes.baseAddress?.assumingMemoryBound(to:Int8.self),bytes.count,salt,salt.count,CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),1003,&key,16)
        }
        guard derived == kCCSuccess else { throw QuotaError(message:"无法解密 Claude 桌面端登录") }
        let ciphertext = encrypted.dropFirst(3), capacity = ciphertext.count + kCCBlockSizeAES128
        var output = [UInt8](repeating:0,count:capacity), count = 0
        let status = ciphertext.withUnsafeBytes { bytes in
            CCCrypt(CCOperation(kCCDecrypt),CCAlgorithm(kCCAlgorithmAES),CCOptions(kCCOptionPKCS7Padding),key,16,Array(repeating:UInt8(32),count:16),bytes.baseAddress,bytes.count,&output,capacity,&count)
        }
        guard status == kCCSuccess else { throw QuotaError(message:"无法解密 Claude 桌面端登录") }
        return Data(output.prefix(count))
    }
    private func activeOrganization(password: Data) throws -> String? {
        let paths = ["Cookies","Network/Cookies"]
        for path in paths {
            let url = directory.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath:url.path) else { continue }
            var db: OpaquePointer?
            guard sqlite3_open_v2(url.path,&db,SQLITE_OPEN_READONLY|SQLITE_OPEN_NOMUTEX,nil) == SQLITE_OK else { if let db { sqlite3_close(db) }; throw QuotaError(message:"无法读取 Claude 桌面端组织选择；稍后刷新") }
            defer { sqlite3_close(db) }
            sqlite3_busy_timeout(db,200)
            var statement: OpaquePointer?
            let sql = "SELECT host_key,value,encrypted_value FROM cookies WHERE name='lastActiveOrg' AND host_key IN ('claude.ai','.claude.ai')"
            guard sqlite3_prepare_v2(db,sql,-1,&statement,nil) == SQLITE_OK else { throw QuotaError(message:"无法读取 Claude 桌面端组织选择；稍后刷新") }
            defer { sqlite3_finalize(statement) }
            var organizations = Set<String>(), sawSelection = false
            var step = sqlite3_step(statement)
            while step == SQLITE_ROW {
                sawSelection = true
                defer { step = sqlite3_step(statement) }
                if let text = sqlite3_column_text(statement,1), let id = UUID(uuidString:String(cString:text)) { organizations.insert(id.uuidString.lowercased()); continue }
                let count = Int(sqlite3_column_bytes(statement,2))
                guard count > 0, let bytes = sqlite3_column_blob(statement,2) else { continue }
                let decoded = try decrypt(Data(bytes:bytes,count:count),password:password)
                // New Chromium cookie stores prepend a 32-byte host digest.
                let host = sqlite3_column_text(statement,0).map { String(cString:$0) } ?? ""
                let prefix = Data(SHA256.hash(data:Data(host.utf8)))
                let candidates = decoded.starts(with:prefix) ? [Data(decoded.dropFirst(32))] : [decoded]
                for candidate in candidates {
                    if let text = String(data:candidate,encoding:.utf8), let id = UUID(uuidString:text) { organizations.insert(id.uuidString.lowercased()) }
                }
            }
            guard step == SQLITE_DONE, !sawSelection || organizations.count == 1 else { throw QuotaError(message:"无法读取 Claude 桌面端组织选择；稍后刷新") }
            if organizations.count == 1 { return organizations.first }
        }
        return nil
    }
    // Recheck local selection during cooldown without prompting or making an HTTP request.
    func selectionHint() -> String? {
        guard let account = accountHint() else { return nil }
        guard cachedPassword != nil else { return account + "|unverified" }
        return (try? read(allowPrompt:false).target) ?? account + "|unavailable"
    }
    func read(allowPrompt: Bool) throws -> ClaudeDesktopContext {
        let root = try config()
        guard let rawID = root["lastKnownAccountUuid"] as? String, let account = UUID(uuidString:rawID)?.uuidString.lowercased() else { throw QuotaError(message:"未找到 Claude 桌面端登录；请先在桌面端登录") }
        guard let encoded = root["oauth:tokenCacheV2"] as? String, let encrypted = Data(base64Encoded:encoded) else { throw QuotaError(message:"Claude 桌面端未提供额度登录；请打开桌面端更新登录") }
        let password = try password(allowPrompt:allowPrompt)
        let data = try decrypt(encrypted,password:password)
        cachedPassword = password
        guard let cache = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw QuotaError(message:"Claude 桌面端登录记录无效；请在桌面端重新登录") }
        var candidates: [(key:String,organization:String,scopes:[String],token:String?)] = []
        for (key,value) in cache {
            let parts = key.components(separatedBy:"|")
            guard parts.count == 2, parts[0].hasPrefix("acct:"), UUID(uuidString:String(parts[0].dropFirst(5)))?.uuidString.lowercased() == account,
                  let audience = parts[1].range(of:":https://api.anthropic.com:"), let entry = value as? [String:Any] else { continue }
            let owner = parts[1][..<audience.lowerBound].split(separator:":")
            guard owner.count == 2, let org = UUID(uuidString:String(owner[1]))?.uuidString.lowercased() else { continue }
            let scopes = parts[1][audience.upperBound...].split(separator:" ").map(String.init)
            let expiry = entry["expiresAt"] as? Double ?? 0
            let token = entry["token"] as? String
            let valid = token.map { !$0.isEmpty && $0.utf8.count <= 16384 && $0.utf8.allSatisfy { $0 > 32 && $0 < 127 } } ?? false
            candidates.append((key,org,scopes,valid && scopes.contains("user:profile") && expiry.isFinite && expiry > now().timeIntervalSince1970*1000 ? token : nil))
        }
        let organizations = Set(candidates.map(\.organization))
        let active = try activeOrganization(password:password)
        let organization = active ?? (organizations.count == 1 ? organizations.first : nil)
        guard let organization, organizations.contains(organization) else { throw QuotaError(message:"无法确定 Claude 桌面端当前组织；请在桌面端选择组织后刷新") }
        // Prefer the least-privileged profile credential, never another account's longest expiry.
        let available = candidates.filter { $0.organization == organization && $0.token != nil }.sorted { $0.scopes.count == $1.scopes.count ? $0.key < $1.key : $0.scopes.count < $1.scopes.count }
        return ClaudeDesktopContext(accountID:account,organizationID:organization,token:available.first?.token)
    }
}
