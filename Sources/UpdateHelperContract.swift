import Foundation
import Darwin

enum UpdatePaths {
    // Foundation may preserve different file/directory URL hints across macOS
    // versions. Filesystem identity is the standardized path, not URL spelling.
    static func samePath(_ a: URL, _ b: URL) -> Bool { a.standardizedFileURL.path == b.standardizedFileURL.path }
    static func rejectLinks(_ url: URL) throws {
        var current = URL(fileURLWithPath:"/",isDirectory:true)
        for component in url.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            var value = stat()
            guard lstat(current.path,&value) == 0, (value.st_mode & S_IFMT) != S_IFLNK else { throw UpdateError("更新路径不存在或包含符号链接") }
        }
    }
    static func root(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL { home.appendingPathComponent("Library/Caches/local.codexquota/Updates",isDirectory:true) }
    static func createStage() throws -> URL {
        let parent = root()
        try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try rejectLinks(parent)
        let attributes = try FileManager.default.attributesOfItem(atPath:parent.path)
        guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw UpdateError("更新缓存所有者无效") }
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:parent.path)
        var template = Array(parent.appendingPathComponent("stage.XXXXXX").path.utf8CString)
        guard mkdtemp(&template) != nil else { throw UpdateError("无法创建私有更新目录") }
        return URL(fileURLWithPath:String(cString:template),isDirectory:true)
    }
    static func clean(_ directory: URL) {
        guard samePath(directory.deletingLastPathComponent(),root()), directory.lastPathComponent.hasPrefix("stage.") else { return }
        try? FileManager.default.removeItem(at:directory)
    }
}
struct UpdateTarget {
    let url: URL
    let isUser: Bool
    static func resolve(runningBundle: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> Self {
        let path = runningBundle.standardizedFileURL
        let user = home.appendingPathComponent("Applications/QuotaNest.app").standardizedFileURL
        guard UpdatePaths.samePath(path,user) || path.path == "/Applications/QuotaNest.app" else { throw UpdateError("请将应用安装在 ~/Applications 或 /Applications 后更新") }
        try UpdatePaths.rejectLinks(path)
        return Self(url:path,isUser:UpdatePaths.samePath(path,user))
    }
}
protocol UpdateCommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> Data
}
struct UpdateCommandRunner: UpdateCommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval = 30) throws -> Data {
        var template = Array((NSTemporaryDirectory() + "quotanest-command.XXXXXX").utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw UpdateError("无法创建更新进程") }
        let output = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        let path = String(cString:template)
        defer { try? output.close(); unlink(path) }
        let process = Process(); process.executableURL = URL(fileURLWithPath:executable); process.arguments = arguments
        process.environment = ["PATH":"/usr/bin:/bin:/usr/sbin:/sbin","HOME":FileManager.default.homeDirectoryForCurrentUser.path]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval:0.05) }
        if process.isRunning { process.terminate(); Thread.sleep(forTimeInterval:0.2); if process.isRunning { kill(process.processIdentifier,SIGKILL) }; process.waitUntilExit(); throw UpdateError("更新安装操作超时") }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError("更新安装验证或系统操作失败") }
        try output.seek(toOffset:0)
        let data = try output.read(upToCount:1_048_577) ?? Data()
        guard data.count <= 1_048_576 else { throw UpdateError("更新进程输出超过限制") }; return data
    }
}
enum UpdateBundleValidator {
    static func validate(at app: URL, expectedVersion: DottedVersion, runner: UpdateCommandRunning = UpdateCommandRunner()) throws {
        try UpdatePaths.rejectLinks(app)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at:app,includingPropertiesForKeys:[.isRegularFileKey,.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey],options:[],errorHandler:{ _,_ in false }) else { throw UpdateError("无法读取更新应用") }
        var count = 0, size = 0
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys:[.isRegularFileKey,.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey])
            count += 1; size += values.fileSize ?? 0
            guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true, count < 10000, size <= 268_435_456 else { throw UpdateError("更新应用包含不受支持的文件或超过大小限制") }
        }
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let attributes = try? fm.attributesOfItem(atPath:plistURL.path), (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 65536,
              let plist = try PropertyListSerialization.propertyList(from:Data(contentsOf:plistURL),options:[],format:nil) as? [String:Any],
              plist["CFBundleIdentifier"] as? String == "local.codexquota", plist["CFBundleExecutable"] as? String == "QuotaNest",
              plist["CFBundleShortVersionString"] as? String == expectedVersion.text,
              let minimum = plist["LSMinimumSystemVersion"] as? String, let required = DottedVersion(minimum) else { throw UpdateError("更新应用身份或版本不匹配") }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        guard required <= DottedVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")! else { throw UpdateError("新版本需要更高版本的 macOS") }
        for path in ["Contents/MacOS/QuotaNest","Contents/Resources/quotanest-update-helper","Contents/Resources/AppIcon.icns"] {
            guard try app.appendingPathComponent(path).resourceValues(forKeys:[.isRegularFileKey]).isRegularFile == true else { throw UpdateError("更新应用缺少必要资源") }
        }
        guard try app.appendingPathComponent("Contents/Resources/provider-marks").resourceValues(forKeys:[.isDirectoryKey]).isDirectory == true else { throw UpdateError("更新应用缺少平台标识") }
        for path in ["Contents/MacOS/QuotaNest","Contents/Resources/quotanest-update-helper"] {
            let executable = app.appendingPathComponent(path)
            let mode = (try fm.attributesOfItem(atPath:executable.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
            guard mode & 0o111 != 0 else { throw UpdateError("更新应用或助手缺少执行权限") }
            let architectures = String(decoding:try runner.run("/usr/bin/lipo",arguments:["-archs",executable.path],timeout:15),as:UTF8.self).split(whereSeparator: { $0.isWhitespace })
            guard architectures.contains("arm64"), architectures.contains("x86_64") else { throw UpdateError("更新应用或助手不是通用架构") }
        }
        _ = try runner.run("/usr/bin/codesign",arguments:["--verify","--deep","--strict",app.path],timeout:30)
    }
}
struct UpdateHelperRequest: Codable {
    let parentPID: Int32
    let userID: UInt32
    let homePath: String
    let stagePath: String
    let targetPath: String
    let version: String
    let loginEnabled: Bool
    var directory: URL { URL(fileURLWithPath:stagePath,isDirectory:true) }
    var stagedApp: URL { directory.appendingPathComponent("QuotaNest.app") }
    var statusURL: URL { directory.appendingPathComponent("status.json") }
    func validate() throws {
        guard userID >= 501, parentPID > 1, let user = getpwuid(userID), homePath == String(cString:user.pointee.pw_dir), DottedVersion(version) != nil else { throw UpdateError("更新请求身份无效") }
        let home = URL(fileURLWithPath:homePath)
        guard UpdatePaths.samePath(directory.deletingLastPathComponent(),UpdatePaths.root(home:home)), directory.lastPathComponent.hasPrefix("stage."), directory.path == stagePath else { throw UpdateError("更新暂存路径无效") }
        try UpdatePaths.rejectLinks(directory)
        let attributes = try FileManager.default.attributesOfItem(atPath:directory.path)
        guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == userID, (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else { throw UpdateError("更新暂存权限无效") }
        _ = try UpdateTarget.resolve(runningBundle:URL(fileURLWithPath:targetPath),home:home)
        if geteuid() != 0 { guard geteuid() == userID, targetPath != "/Applications/QuotaNest.app" else { throw UpdateError("更新安装权限不足") } }
    }
    static func load(_ url: URL) throws -> Self {
        try UpdatePaths.rejectLinks(url)
        let attributes = try FileManager.default.attributesOfItem(atPath:url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular, (attributes[.size] as? NSNumber)?.intValue ?? Int.max < 16384, (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600 else { throw UpdateError("更新请求文件无效") }
        let request = try JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
        guard UpdatePaths.samePath(url,request.directory.appendingPathComponent("request.json")), (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == request.userID else { throw UpdateError("更新请求路径或所有者无效") }
        try request.validate(); return request
    }
}
struct UpdateInstallStatus: Codable {
    let state: String
    let message: String
    var arguments: [String]? = nil
    var localizedMessage: String { Localization.shared.text(message,arguments ?? []) }
    var failure: UpdateError { UpdateError(message,arguments:arguments ?? []) }
}
