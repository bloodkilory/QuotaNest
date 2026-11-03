import Foundation
import SQLite3
import CryptoKit
useTestLanguage()
func check(_ value: Bool, _ message: String) { if !value { fatalError(message) }; print("PASS " + message) }
let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at:home,withIntermediateDirectories:true)
defer { try? FileManager.default.removeItem(at:home) }
let now = Date(timeIntervalSince1970:2_000_000_000)
func entry(_ token: String, expired: Bool = false) -> [String:Any] { ["token":token,"expiresAt":now.addingTimeInterval(expired ? -1 : 600).timeIntervalSince1970*1000] }
try writeDesktopConfig(home,entries:[desktopCacheKey():entry("desktop-profile"),desktopCacheKey(scopes:"user:inference user:profile"):entry("desktop-code"),desktopCacheKey(account:desktopAccountB):entry("other-account")])
let store = testDesktopStore(home,now:{ now })
check(store.accountHint() == desktopAccountA,"desktop account hint follows current account")
let context = try store.read(allowPrompt:false)
check(context.accountID == desktopAccountA && context.organizationID == desktopOrg,"selected identity belongs to desktop account")
check(context.token == "desktop-profile","prefer profile-only credential within same account and organization")
try writeDesktopConfig(home,account:desktopAccountB,entries:[desktopCacheKey():entry("old-account"),desktopCacheKey(account:desktopAccountB):entry("new-account")])
check(try store.read(allowPrompt:false).token == "new-account","desktop account switch never uses old account token")
try writeDesktopConfig(home,entries:[desktopCacheKey():entry("expired",expired:true)])
let expired = try store.read(allowPrompt:false)
check(expired.token == nil && expired.accountID == desktopAccountA && expired.organizationID == desktopOrg,"expired desktop token keeps target identity for verified CLI backup")
try writeDesktopConfig(home,entries:[desktopCacheKey(scopes:"user:inference"):entry("inference-only")])
check(try store.read(allowPrompt:false).token == nil,"inference-only credential is not a quota credential")
let otherOrg = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
try writeDesktopConfig(home,entries:[desktopCacheKey():entry("one"),desktopCacheKey(org:otherOrg):entry("two")])
do { _ = try store.read(allowPrompt:false); fatalError("ambiguous organization accepted") } catch { print("PASS unknown active organization fails instead of selecting arbitrary quota") }
let cookie=home.appendingPathComponent("Library/Application Support/Claude/Cookies")
var db: OpaquePointer?
check(sqlite3_open(cookie.path,&db) == SQLITE_OK,"synthetic organization store opens")
let encryptedOrg=encryptedDesktopBytes(Data(SHA256.hash(data:Data(".claude.ai".utf8)))+Data(otherOrg.utf8)).map { String(format:"%02x",$0) }.joined()
check(sqlite3_exec(db,"CREATE TABLE cookies(host_key TEXT,name TEXT,value TEXT,encrypted_value BLOB); INSERT INTO cookies VALUES('.claude.ai','lastActiveOrg','',x'\(encryptedOrg)');",nil,nil,nil)==SQLITE_OK,"synthetic active organization saved")
sqlite3_close(db)
check(try store.read(allowPrompt:false).organizationID==otherOrg,"multiple organizations follow desktop active organization")
try writeDesktopConfig(home,entries:[desktopCacheKey():entry("old-organization")])
do { _ = try store.read(allowPrompt:false); fatalError("old single-organization cache overrode active organization") } catch { print("PASS active organization without a matching credential never selects old organization") }
try selectDesktopOrganization(home,desktopOrg)
try writeDesktopConfig(home,entries:[desktopCacheKey():entry("desktop-profile")])
let denied = ClaudeDesktopCredentials(home:home,now:{ now },keyReader:{ _ in throw QuotaError(message:"Denied") })
do { _ = try denied.read(allowPrompt:false); fatalError("keychain rejection bypassed") } catch { print("PASS denied keychain access stays denied") }
let file=home.appendingPathComponent("Library/Application Support/Claude/config.json")
try JSONSerialization.data(withJSONObject:["lastKnownAccountUuid":desktopAccountA,"oauth:tokenCacheV2":"malformed-encrypted-cache"]).write(to:file)
do { _ = try store.read(allowPrompt:false); fatalError("invalid encrypted cache accepted") } catch { print("PASS malformed encrypted cache rejected") }
try writeDesktopConfig(home,entries:[desktopCacheKey():entry("desktop-profile")])
try selectDesktopOrganization(home,desktopOrg)
var locked: OpaquePointer?
check(sqlite3_open(cookie.path,&locked)==SQLITE_OK,"organization contention test opens own database")
check(sqlite3_exec(locked,"BEGIN EXCLUSIVE",nil,nil,nil)==SQLITE_OK,"organization database is held by synthetic writer")
do { _ = try store.read(allowPrompt:false); fatalError("busy organization store selected cached organization") } catch { print("PASS unreadable active organization never falls back to old cached organization") }
sqlite3_exec(locked,"ROLLBACK",nil,nil,nil)
check(sqlite3_exec(locked,"UPDATE cookies SET value='invalid',encrypted_value=x''",nil,nil,nil)==SQLITE_OK,"invalid synthetic organization prepared")
sqlite3_close(locked)
do { _ = try store.read(allowPrompt:false); fatalError("invalid organization selected cached organization") } catch { print("PASS malformed active organization is rejected") }
try selectDesktopOrganization(home,desktopOrg)
var keyReads=0
let cached=testDesktopStore(home,now:{ now },read:{ keyReads+=1 })
_ = try cached.read(allowPrompt:false)
_ = cached.selectionHint()
check(keyReads==1,"selection recheck uses only process-local key cache")
_ = try cached.read(allowPrompt:true)
check(keyReads==2,"explicit authorization rechecks keychain reader")
print("Desktop credential selection verified with synthetic encrypted data")
let external=try QuotaSnapshot.decode(Data(#"{"rateLimits":null,"rateLimitsByLimitId":null,"loginSource":"untrusted source"}"#.utf8))
check(external.loginSource==nil,"external quota response cannot set trusted login source")
