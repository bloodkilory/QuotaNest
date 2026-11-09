import Foundation
import CryptoKit
useTestLanguage()
func check(_ value: Bool, _ name: String) { if !value { fatalError("FAIL " + name) }; print("PASS " + name) }
func rejects(_ name: String, _ body: () throws -> Void) { do { try body(); fatalError("FAIL " + name) } catch { print("PASS " + name) } }
func json(tag: String = "v1.7.0", draft: Bool = false, pre: Bool = false, duplicate: Bool = false, url: String = "https://api.github.com/repos/bloodkilory/QuotaNest/releases/assets/1") -> Data {
    var assets: [[String: Any]] = [["name":"QuotaNest-1.7.0-universal.dmg", "url":url, "size":100], ["name":"SHA256SUMS.txt", "url":"https://api.github.com/repos/bloodkilory/QuotaNest/releases/assets/2", "size":96]]
    if duplicate { assets.append(assets[0]) }
    return try! JSONSerialization.data(withJSONObject:["tag_name":tag,"draft":draft,"prerelease":pre,"assets":assets])
}
let current = DottedVersion("1.6.0")!
let prospectivePath = FileManager.default.currentDirectoryPath + "/.build/nonexistent-application.app"
check(UpdatePaths.samePath(URL(fileURLWithPath:prospectivePath,isDirectory:true),URL(fileURLWithPath:prospectivePath,isDirectory:false)), "file/directory URL hints do not change filesystem identity")
check(DottedVersion("1.10.0")! > DottedVersion("1.9.9")!, "numeric version order")
check(DottedVersion("1.7")! == DottedVersion("1.7.0")!, "zero-padded equality")
for bad in ["", "1..7", "1.7-beta", "-1.0", "1.+7", "1. 7", "9999999999999999999999"] { check(DottedVersion(bad) == nil, "invalid version " + bad) }
guard case .available(let release) = try ReleaseManifest.release(from: json(), currentVersion: current) else { fatalError("new release") }
check(release.version == DottedVersion("1.7.0")!, "new stable release available")
guard case .upToDate = try ReleaseManifest.release(from: json(), currentVersion: DottedVersion("1.8.0")!) else { fatalError("older release") }
rejects("draft rejected") { _ = try ReleaseManifest.release(from:json(draft:true),currentVersion:current) }
rejects("prerelease rejected") { _ = try ReleaseManifest.release(from:json(pre:true),currentVersion:current) }
rejects("duplicate asset rejected") { _ = try ReleaseManifest.release(from:json(duplicate:true),currentVersion:current) }
rejects("wrong tag rejected") { _ = try ReleaseManifest.release(from:json(tag:"v1.8.0"),currentVersion:current) }
rejects("foreign asset rejected") { _ = try ReleaseManifest.release(from:json(url:"https://evil.example/a"),currentVersion:current) }
let hash = String(repeating:"a", count:64), name = release.filename
let manifest = Data((hash + "  " + name + "\n").utf8)
check(try ReleaseManifest.digest(for:name,manifest:manifest) == Data(repeating:0xaa,count:32), "digest parsed")
rejects("duplicate manifest rows rejected") { _ = try ReleaseManifest.digest(for:name,manifest:manifest + manifest) }
rejects("wrong filename rejected") { _ = try ReleaseManifest.digest(for:name,manifest:Data((hash + "  other.dmg\n").utf8)) }
rejects("bad digest rejected") { _ = try ReleaseManifest.digest(for:name,manifest:Data(("xyz  " + name).utf8)) }
var crossPlatform = try JSONSerialization.jsonObject(with:json()) as! [String:Any]
var crossAssets = crossPlatform["assets"] as! [[String:Any]]
crossAssets.append(["name":"QuotaNest-1.7.0-windows-x64-setup.exe","url":"https://api.github.com/repos/bloodkilory/QuotaNest/releases/assets/3","size":200])
crossPlatform["assets"] = crossAssets
guard case .available(let macOnly) = try ReleaseManifest.release(from:JSONSerialization.data(withJSONObject:crossPlatform),currentVersion:current) else { fatalError("cross-platform release") }
check(macOnly.filename == name,"Mac updater selects DMG from a cross-platform release")
let windowsLine = String(repeating:"b",count:64) + "  QuotaNest-1.7.0-windows-x64-setup.exe\n"
for combined in [Data(windowsLine.utf8) + manifest,manifest + Data(windowsLine.utf8)] {
    check(try ReleaseManifest.digest(for:name,manifest:combined) == Data(repeating:0xaa,count:32),"shared checksum selects Mac digest regardless of Windows row order")
}
check(ReleaseManifest.matches(Data([1,2]),Data([1,2])), "digest equality")
check(!ReleaseManifest.matches(Data([1,2]),Data([1,3])), "digest inequality")

check(!UpdateRedirectPolicy.allows(URL(string:"https://release-assets.githubusercontent.com/a")!, asset:false, count:0), "metadata redirects rejected")
check(UpdateRedirectPolicy.allows(URL(string:"https://release-assets.githubusercontent.com/a?signature=x")!, asset:true, count:0), "GitHub asset redirect allowed")
for url in ["http://release-assets.githubusercontent.com/a", "https://evil.example/a", "https://release-assets.githubusercontent.com:444/a", "https://user@objects.githubusercontent.com/a"] {
    check(!UpdateRedirectPolicy.allows(URL(string:url)!,asset:true,count:0), "unsafe redirect rejected")
}
check(!UpdateRedirectPolicy.allows(URL(string:"https://objects.githubusercontent.com/a")!,asset:true,count:1), "second redirect rejected")
final class FixtureProtocol: URLProtocol {
    static var body = Data()
    static var status = 200
    static var responses: [String:Data] = [:]
    static var requests: [URL] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request.url!)
        let response = HTTPURLResponse(url:request.url!,statusCode:Self.status,httpVersion:nil,headerFields:nil)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Self.responses[request.url!.path] ?? Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureProtocol.self]
let transfer = UpdateTransfer(configuration:config)
FixtureProtocol.body = Data("okay".utf8)
check(try transfer.fetch(ReleaseUpdateClient.releaseURL, asset:false, limit:10) == FixtureProtocol.body, "bounded transfer succeeds")
rejects("streaming size cap") { _ = try transfer.fetch(ReleaseUpdateClient.releaseURL,asset:false,limit:2) }
FixtureProtocol.status = 403
rejects("HTTP failure") { _ = try transfer.fetch(ReleaseUpdateClient.releaseURL,asset:false,limit:10) }
FixtureProtocol.status = 200
transfer.cancel()
rejects("cancelled transfer") { _ = try transfer.fetch(ReleaseUpdateClient.releaseURL,asset:false,limit:10) }

let binary = Data("verified installation image".utf8)
let binaryHash = SHA256.hash(data:binary).map { String(format:"%02x",$0) }.joined()
FixtureProtocol.responses = [release.checksumURL.path:Data((binaryHash + "  " + name + "\n").utf8),release.dmgURL.path:binary]
FixtureProtocol.requests = []
let downloadClient = ReleaseUpdateClient(transfer:UpdateTransfer(configuration:config))
let downloaded = DispatchSemaphore(value:0)
var downloadResult: Result<VerifiedUpdateDMG,Error>?
downloadClient.download(release) { downloadResult = $0; downloaded.signal() }
check(downloaded.wait(timeout:.now()+10) == .success, "download fixture completes")
let verified = try downloadResult!.get()
check(try Data(contentsOf:verified.fileURL) == binary, "verified bytes saved")
UpdatePaths.clean(verified.fileURL.deletingLastPathComponent())
check(FixtureProtocol.requests == [release.checksumURL,release.dmgURL], "manifest downloaded before DMG")
FixtureProtocol.responses[release.checksumURL.path] = manifest
downloadClient.download(release) { downloadResult = $0; downloaded.signal() }
check(downloaded.wait(timeout:.now()+10) == .success, "mismatch fixture completes")
rejects("download digest mismatch rejected") { _ = try downloadResult!.get() }
FixtureProtocol.responses[release.checksumURL.path] = Data("invalid".utf8)
FixtureProtocol.requests = []
downloadClient.download(release) { downloadResult = $0; downloaded.signal() }
check(downloaded.wait(timeout:.now()+10) == .success, "bad manifest fixture completes")
rejects("invalid manifest rejected before download") { _ = try downloadResult!.get() }
check(FixtureProtocol.requests == [release.checksumURL], "bad manifest prevents DMG transfer")
downloadClient.cancel()

let temp = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/quotanest-update-tests-" + UUID().uuidString)
try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
defer { try? FileManager.default.removeItem(at:temp) }
let home = temp.appendingPathComponent("home")
let app = home.appendingPathComponent("Applications/QuotaNest.app")
try FileManager.default.createDirectory(at:app,withIntermediateDirectories:true)
check(try UpdateTarget.resolve(runningBundle:app,home:home).isUser, "user Applications accepted")
check(try UpdateTarget.resolve(runningBundle:URL(fileURLWithPath:app.path,isDirectory:true),home:home).isUser, "directory URL spelling accepted")
rejects("arbitrary location rejected") { _ = try UpdateTarget.resolve(runningBundle:temp.appendingPathComponent("QuotaNest.app"),home:home) }
let link = temp.appendingPathComponent("linked.app")
try FileManager.default.createSymbolicLink(at:link,withDestinationURL:app)
rejects("symlink target rejected") { _ = try UpdateTarget.resolve(runningBundle:link,home:home) }
struct FixtureRunner: UpdateCommandRunning {
    var architectures = "x86_64 arm64"
    var helperArchitectures = "x86_64 arm64"
    var signed = true
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> Data {
        if executable == "/usr/bin/lipo" { return Data((arguments.last?.hasSuffix("quotanest-update-helper") == true ? helperArchitectures : architectures).utf8) }
        if !signed { throw UpdateError("bad signature") }
        return Data()
    }
}
func fixtureApp(_ path: URL, id: String = "local.codexquota", version: String = "1.7.0") throws {
    for dir in ["Contents/MacOS","Contents/Resources/provider-marks"] { try FileManager.default.createDirectory(at:path.appendingPathComponent(dir),withIntermediateDirectories:true) }
    let plist: [String:Any] = ["CFBundleIdentifier":id,"CFBundleExecutable":"QuotaNest","CFBundleShortVersionString":version,"LSMinimumSystemVersion":"13.0"]
    try PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0).write(to:path.appendingPathComponent("Contents/Info.plist"))
    for file in ["Contents/MacOS/QuotaNest","Contents/Resources/quotanest-update-helper","Contents/Resources/AppIcon.icns"] { try Data("fixture".utf8).write(to:path.appendingPathComponent(file)) }
    for file in ["Contents/MacOS/QuotaNest","Contents/Resources/quotanest-update-helper"] { try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:path.appendingPathComponent(file).path) }
}
try fixtureApp(app)
try UpdateBundleValidator.validate(at:app,expectedVersion:release.version,runner:FixtureRunner())
try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:app.appendingPathComponent("Contents/MacOS/QuotaNest").path)
rejects("non-executable main binary rejected") { try UpdateBundleValidator.validate(at:app,expectedVersion:release.version,runner:FixtureRunner()) }
try fixtureApp(app)
try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:app.appendingPathComponent("Contents/Resources/quotanest-update-helper").path)
rejects("non-executable helper rejected") { try UpdateBundleValidator.validate(at:app,expectedVersion:release.version,runner:FixtureRunner()) }
try fixtureApp(app)
rejects("helper architecture rejected") { try UpdateBundleValidator.validate(at:app,expectedVersion:release.version,runner:FixtureRunner(helperArchitectures:"x86_64")) }
rejects("architecture rejected") { try UpdateBundleValidator.validate(at:app,expectedVersion:release.version,runner:FixtureRunner(architectures:"x86_64")) }
rejects("signature rejected") { try UpdateBundleValidator.validate(at:app,expectedVersion:release.version,runner:FixtureRunner(signed:false)) }
rejects("bundle version rejected") { try UpdateBundleValidator.validate(at:app,expectedVersion:current,runner:FixtureRunner()) }
try fixtureApp(app,id:"other.app")
rejects("bundle identifier rejected") { try UpdateBundleValidator.validate(at:app,expectedVersion:release.version,runner:FixtureRunner()) }
try fixtureApp(app)
try FileManager.default.createSymbolicLink(at:app.appendingPathComponent("Contents/evil"),withDestinationURL:temp)
rejects("nested symlink rejected") { try UpdateBundleValidator.validate(at:app,expectedVersion:release.version,runner:FixtureRunner()) }

let transaction = temp.appendingPathComponent("transaction")
try FileManager.default.createDirectory(at:transaction,withIntermediateDirectories:true)
let old = transaction.appendingPathComponent("QuotaNest.app"), staged = transaction.appendingPathComponent("staged.app")
try FileManager.default.createDirectory(at:old,withIntermediateDirectories:true)
try Data("old".utf8).write(to:old.appendingPathComponent("value"))
try FileManager.default.createDirectory(at:staged,withIntermediateDirectories:true)
try Data("new".utf8).write(to:staged.appendingPathComponent("value"))
var validationCount = 0
rejects("failed replacement validation restores backup") {
    _ = try UpdateReplacement.install(staged:staged,target:old) { _ in
        validationCount += 1
        if validationCount == 2 { throw UpdateError("injected post-copy failure") }
    }
}
check(try String(contentsOf:old.appendingPathComponent("value"),encoding:.utf8) == "old", "old bundle restored")
let backup = try UpdateReplacement.install(staged:staged,target:old) { _ in }
check(try String(contentsOf:old.appendingPathComponent("value"),encoding:.utf8) == "new", "new bundle installed")
check(try String(contentsOf:backup.appendingPathComponent("value"),encoding:.utf8) == "old", "backup preserved")

check(UpdateMenuState.available("1.7.0").title == "发现 v1.7.0", "available menu label")
check(!UpdateMenuState.busy("正在下载…").isActionEnabled, "busy prevents duplicate action")
check(UpdateMenuState.current("1.7.0").isActionEnabled, "manual recheck available")
check(UpdatePrivilegeLauncher.shellQuote("a'b") == "'a'\\''b'", "administrator command arguments quoted")
check(UpdatePrivilegeLauncher.shellQuote("a\n$(touch nope)") == "'a\n$(touch nope)'", "shell metacharacters remain literal")

let helperFile = temp.appendingPathComponent("test helper's binary")
let marker = temp.appendingPathComponent("helper marker")
let trustedHelper = Data("#!/bin/sh\nprintf verified > \"$2\"\n".utf8)
try trustedHelper.write(to:helperFile)
let trustedDigest = SHA256.hash(data:trustedHelper).map { String(format:"%02x",$0) }.joined()
let protectedCommand = try UpdatePrivilegeLauncher.privilegedCommand(helper:helperFile.path,request:marker.path,expectedDigest:trustedDigest)
_ = try UpdateCommandRunner().run("/bin/sh",arguments:["-c",protectedCommand],timeout:15)
check(try String(contentsOf:marker,encoding:.utf8) == "verified", "protected helper copy executes after digest match")
try FileManager.default.removeItem(at:marker)
try Data("#!/bin/sh\nprintf tampered > \"$2\"\n".utf8).write(to:helperFile)
rejects("tampered privileged helper rejected") { _ = try UpdateCommandRunner().run("/bin/sh",arguments:["-c",protectedCommand],timeout:15) }
check(!FileManager.default.fileExists(atPath:marker.path), "tampered helper never executed")
