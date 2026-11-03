import Foundation
import CommonCrypto
import SQLite3
let desktopAccountA = "11111111-1111-4111-8111-111111111111"
let desktopAccountB = "22222222-2222-4222-8222-222222222222"
let desktopOrg = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
let desktopPassword = Data("synthetic-desktop-key".utf8)
func desktopCacheKey(account: String = desktopAccountA, org: String = desktopOrg, scopes: String = "user:profile") -> String {
    "acct:\(account)|33333333-3333-4333-8333-333333333333:\(org):https://api.anthropic.com:\(scopes)"
}
func encryptedDesktopBytes(_ data: Data) -> Data {
    var key = [UInt8](repeating:0,count:16)
    let salt = Array("saltysalt".utf8)
    let derived = desktopPassword.withUnsafeBytes { password in
        CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),password.baseAddress!.assumingMemoryBound(to:Int8.self),password.count,salt,salt.count,CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),1003,&key,key.count)
    }
    precondition(derived == kCCSuccess)
    let capacity = data.count + kCCBlockSizeAES128
    var output = [UInt8](repeating:0,count:capacity), count = 0
    let status = data.withUnsafeBytes { bytes in
        CCCrypt(CCOperation(kCCEncrypt),CCAlgorithm(kCCAlgorithmAES),CCOptions(kCCOptionPKCS7Padding),key,key.count,Array(repeating:UInt8(32),count:16),bytes.baseAddress,data.count,&output,capacity,&count)
    }
    precondition(status == kCCSuccess)
    return Data("v10".utf8)+Data(output.prefix(count))
}
func encryptedDesktopCache(_ object: [String:Any]) throws -> String {
    encryptedDesktopBytes(try JSONSerialization.data(withJSONObject:object)).base64EncodedString()
}
func writeDesktopConfig(_ home: URL, account: String = desktopAccountA, entries: [String:Any]) throws {
    let dir = home.appendingPathComponent("Library/Application Support/Claude")
    try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
    try JSONSerialization.data(withJSONObject:["lastKnownAccountUuid":account,"oauth:tokenCacheV2":encryptedDesktopCache(entries)]).write(to:dir.appendingPathComponent("config.json"))
}
func testDesktopStore(_ home: URL, now: @escaping () -> Date, read: @escaping () -> Void = {}) -> ClaudeDesktopCredentials {
    ClaudeDesktopCredentials(home:home,now:now,keyReader:{ _ in read(); return desktopPassword })
}

func selectDesktopOrganization(_ home: URL, _ org: String) throws {
    let dir=home.appendingPathComponent("Library/Application Support/Claude")
    try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
    var db: OpaquePointer?
    precondition(sqlite3_open(dir.appendingPathComponent("Cookies").path,&db)==SQLITE_OK)
    defer { sqlite3_close(db) }
    let sql="CREATE TABLE IF NOT EXISTS cookies(host_key TEXT,name TEXT,value TEXT,encrypted_value BLOB); DELETE FROM cookies; INSERT INTO cookies VALUES('.claude.ai','lastActiveOrg','\(org)',x'');"
    precondition(sqlite3_exec(db,sql,nil,nil,nil)==SQLITE_OK)
}
