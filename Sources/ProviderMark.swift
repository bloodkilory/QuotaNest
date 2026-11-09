import AppKit

// Official provider assets and monochrome adaptations. See assets/PROVIDER-MARKS.md.
enum ProviderMark {
    private static let officialMarks: [QuotaProviderID: NSImage] = {
        var marks: [QuotaProviderID: NSImage] = [:]
        for provider in [QuotaProviderID.zcode] {
            let name = provider.rawValue + ".png"
            let bundled = Bundle.main.resourceURL?.appendingPathComponent("provider-marks/" + name)
            let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("assets/provider-marks/" + name)
            if let image = [bundled, development].compactMap({ $0 }).compactMap({ NSImage(contentsOf: $0) }).first {
                marks[provider] = image
            }
        }
        return marks
    }()
    private static let deepseek: NSImage? = {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("provider-marks/deepseek.svg")
        let development = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("assets/provider-marks/deepseek.svg")
        return [bundled,development].compactMap { $0 }.compactMap { NSImage(contentsOf:$0) }.first
    }()
    static func drawDeepSeek(in rect: CGRect) {
        guard let image = deepseek else { return }
        let scale = min(rect.width / image.size.width,rect.height / image.size.height)
        let size = NSSize(width:image.size.width * scale,height:image.size.height * scale)
        image.draw(in:NSRect(x:rect.midX - size.width / 2,y:rect.midY - size.height / 2,width:size.width,height:size.height))
    }
    static func draw(_ provider: QuotaProviderID, in rect: CGRect, tint: NSColor = .white) {
        if let image = officialMarks[provider] {
            let scale = min(rect.width / image.size.width, rect.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                 width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(tint.cgColor)
        let path: CGPath
        switch provider {
        case .codex: path = codex
        case .antigravity: path = antigravity
        case .claude: path = claude
        case .zcode: return
        }
        let box = path.boundingBoxOfPath
        let scale = min(rect.width / box.width, rect.height / box.height)
        context.translateBy(x: rect.midX - box.width * scale / 2, y: rect.midY + box.height * scale / 2)
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.addPath(path)
        context.fillPath()
    }
    private static let claude: CGPath = {
        let p = CGMutablePath()
        // Claude Code's terminal mascot, with transparent eyes and four feet.
        let rows = ["00111111100", "11111111111", "11011111011", "11011111011", "11111111111", "00111111100", "00101010100", "00101010100"]
        for (y, row) in rows.enumerated() {
            for (x, pixel) in row.enumerated() where pixel == "1" {
                p.addRect(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return p
    }()
    private static let codex: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 37.5324, y: 16.8707))
        p.addCurve(to: CGPoint(x: 37.9886, y: 12.6859), control1: CGPoint(x: 37.9808, y: 15.5241), control2: CGPoint(x: 38.1363, y: 14.0974))
        p.addCurve(to: CGPoint(x: 36.676, y: 8.68622), control1: CGPoint(x: 37.8409, y: 11.2744), control2: CGPoint(x: 37.3934, y: 9.91076))
        p.addCurve(to: CGPoint(x: 32.0373, y: 4.4985), control1: CGPoint(x: 35.6126, y: 6.83404), control2: CGPoint(x: 33.9882, y: 5.3676))
        p.addCurve(to: CGPoint(x: 25.8215, y: 3.85078), control1: CGPoint(x: 30.0864, y: 3.62941), control2: CGPoint(x: 27.9098, y: 3.40259))
        p.addCurve(to: CGPoint(x: 22.4257, y: 1.36341), control1: CGPoint(x: 24.8796, y: 2.7893), control2: CGPoint(x: 23.7219, y: 1.94125))
        p.addCurve(to: CGPoint(x: 18.3058, y: 0.500197), control1: CGPoint(x: 21.1295, y: 0.785575), control2: CGPoint(x: 19.7249, y: 0.491269))
        p.addCurve(to: CGPoint(x: 12.3614, y: 2.42214), control1: CGPoint(x: 16.1708, y: 0.495044), control2: CGPoint(x: 14.0893, y: 1.16803))
        p.addCurve(to: CGPoint(x: 8.6917, y: 7.47815), control1: CGPoint(x: 10.6335, y: 3.67624), control2: CGPoint(x: 9.34853, y: 5.44666))
        p.addCurve(to: CGPoint(x: 4.8377, y: 9.17505), control1: CGPoint(x: 7.30085, y: 7.76286), control2: CGPoint(x: 5.98686, y: 8.3414))
        p.addCurve(to: CGPoint(x: 2.02839, y: 12.312), control1: CGPoint(x: 3.68854, y: 10.0087), control2: CGPoint(x: 2.73073, y: 11.0782))
        p.addCurve(to: CGPoint(x: 0.721698, y: 18.4228), control1: CGPoint(x: 0.956464, y: 14.1591), control2: CGPoint(x: 0.498905, y: 16.2988))
        p.addCurve(to: CGPoint(x: 3.268, y: 24.1293), control1: CGPoint(x: 0.944492, y: 20.5467), control2: CGPoint(x: 1.83612, y: 22.5449))
        p.addCurve(to: CGPoint(x: 2.81182, y: 28.3141), control1: CGPoint(x: 2.81966, y: 25.4759), control2: CGPoint(x: 2.66413, y: 26.9026))
        p.addCurve(to: CGPoint(x: 4.12437, y: 32.3138), control1: CGPoint(x: 2.95951, y: 29.7256), control2: CGPoint(x: 3.40701, y: 31.0892))
        p.addCurve(to: CGPoint(x: 8.76321, y: 36.5013), control1: CGPoint(x: 5.18791, y: 34.1659), control2: CGPoint(x: 6.8123, y: 35.6322))
        p.addCurve(to: CGPoint(x: 14.9789, y: 37.1492), control1: CGPoint(x: 10.7141, y: 37.3704), control2: CGPoint(x: 12.8907, y: 37.5973))
        p.addCurve(to: CGPoint(x: 18.3747, y: 39.6366), control1: CGPoint(x: 15.9208, y: 38.2107), control2: CGPoint(x: 17.0786, y: 39.0587))
        p.addCurve(to: CGPoint(x: 22.4946, y: 40.4998), control1: CGPoint(x: 19.6709, y: 40.2144), control2: CGPoint(x: 21.0755, y: 40.5087))
        p.addCurve(to: CGPoint(x: 28.4418, y: 38.5772), control1: CGPoint(x: 24.6307, y: 40.5054), control2: CGPoint(x: 26.7133, y: 39.8321))
        p.addCurve(to: CGPoint(x: 32.1119, y: 33.5179), control1: CGPoint(x: 30.1704, y: 37.3223), control2: CGPoint(x: 31.4556, y: 35.5506))
        p.addCurve(to: CGPoint(x: 35.9659, y: 31.821), control1: CGPoint(x: 33.5027, y: 33.2332), control2: CGPoint(x: 34.8167, y: 32.6547))
        p.addCurve(to: CGPoint(x: 38.7752, y: 28.684), control1: CGPoint(x: 37.115, y: 30.9874), control2: CGPoint(x: 38.0728, y: 29.9178))
        p.addCurve(to: CGPoint(x: 40.0789, y: 22.5748), control1: CGPoint(x: 39.8458, y: 26.8371), control2: CGPoint(x: 40.3023, y: 24.6979))
        p.addCurve(to: CGPoint(x: 37.5324, y: 16.8707), control1: CGPoint(x: 39.8556, y: 20.4517), control2: CGPoint(x: 38.9639, y: 18.4544))
        p.closeSubpath()
        p.move(to: CGPoint(x: 22.4978, y: 37.8849))
        p.addCurve(to: CGPoint(x: 17.6994, y: 36.1501), control1: CGPoint(x: 20.7443, y: 37.8874), control2: CGPoint(x: 19.0459, y: 37.2733))
        p.addCurve(to: CGPoint(x: 17.936, y: 36.0161), control1: CGPoint(x: 17.7601, y: 36.117), control2: CGPoint(x: 17.8666, y: 36.0586))
        p.addLine(to: CGPoint(x: 25.9004, y: 31.4156))
        p.addCurve(to: CGPoint(x: 26.3813, y: 30.9378), control1: CGPoint(x: 26.1003, y: 31.3019), control2: CGPoint(x: 26.2663, y: 31.137))
        p.addCurve(to: CGPoint(x: 26.5549, y: 30.2825), control1: CGPoint(x: 26.4964, y: 30.7386), control2: CGPoint(x: 26.5563, y: 30.5124))
        p.addLine(to: CGPoint(x: p.currentPoint.x, y: 19.0542))
        p.addLine(to: CGPoint(x: 29.9213, y: 20.998))
        p.addCurve(to: CGPoint(x: 29.9656, y: 21.0359), control1: CGPoint(x: 29.9389, y: 21.0068), control2: CGPoint(x: 29.9541, y: 21.0198))
        p.addCurve(to: CGPoint(x: 29.9867, y: 21.0902), control1: CGPoint(x: 29.977, y: 21.052), control2: CGPoint(x: 29.9842, y: 21.0707))
        p.addLine(to: CGPoint(x: p.currentPoint.x, y: 30.3889))
        p.addCurve(to: CGPoint(x: 27.7909, y: 35.6841), control1: CGPoint(x: 29.9842, y: 32.375), control2: CGPoint(x: 29.1946, y: 34.2791))
        p.addCurve(to: CGPoint(x: 22.4978, y: 37.8849), control1: CGPoint(x: 26.3872, y: 37.0892), control2: CGPoint(x: 24.4838, y: 37.8806))
        p.closeSubpath()
        p.move(to: CGPoint(x: 6.39227, y: 31.0064))
        p.addCurve(to: CGPoint(x: 5.49804, y: 25.9832), control1: CGPoint(x: 5.51397, y: 29.4888), control2: CGPoint(x: 5.19742, y: 27.7107))
        p.addCurve(to: CGPoint(x: 5.73461, y: 26.1244), control1: CGPoint(x: 5.55718, y: 26.0187), control2: CGPoint(x: 5.66048, y: 26.0818))
        p.addLine(to: CGPoint(x: 13.699, y: 30.7248))
        p.addCurve(to: CGPoint(x: 14.3532, y: 30.902), control1: CGPoint(x: 13.8975, y: 30.8408), control2: CGPoint(x: 14.1233, y: 30.902))
        p.addCurve(to: CGPoint(x: 15.0073, y: 30.7248), control1: CGPoint(x: 14.583, y: 30.902), control2: CGPoint(x: 14.8088, y: 30.8408))
        p.addLine(to: CGPoint(x: 24.731, y: 25.1103))
        p.addLine(to: CGPoint(x: p.currentPoint.x, y: 28.9979))
        p.addCurve(to: CGPoint(x: 24.7199, y: 29.0556), control1: CGPoint(x: 24.7321, y: 29.0177), control2: CGPoint(x: 24.7283, y: 29.0376))
        p.addCurve(to: CGPoint(x: 24.6829, y: 29.1012), control1: CGPoint(x: 24.7115, y: 29.0736), control2: CGPoint(x: 24.6988, y: 29.0893))
        p.addLine(to: CGPoint(x: 16.6317, y: 33.7497))
        p.addCurve(to: CGPoint(x: 10.9447, y: 34.4954), control1: CGPoint(x: 14.9096, y: 34.7416), control2: CGPoint(x: 12.8643, y: 35.0097))
        p.addCurve(to: CGPoint(x: 6.39227, y: 31.0064), control1: CGPoint(x: 9.02506, y: 33.9811), control2: CGPoint(x: 7.38785, y: 32.7263))
        p.closeSubpath()
        p.move(to: CGPoint(x: 4.29707, y: 13.6194))
        p.addCurve(to: CGPoint(x: 8.19885, y: 10.3327), control1: CGPoint(x: 5.17156, y: 12.0998), control2: CGPoint(x: 6.55279, y: 10.9364))
        p.addCurve(to: CGPoint(x: 8.19491, y: 10.6071), control1: CGPoint(x: 8.19885, y: 10.4013), control2: CGPoint(x: 8.19491, y: 10.5228))
        p.addLine(to: CGPoint(x: p.currentPoint.x, y: 19.808))
        p.addCurve(to: CGPoint(x: 8.36823, y: 20.4629), control1: CGPoint(x: 8.19351, y: 20.0378), control2: CGPoint(x: 8.25334, y: 20.2638))
        p.addCurve(to: CGPoint(x: 8.84863, y: 20.9404), control1: CGPoint(x: 8.48312, y: 20.6619), control2: CGPoint(x: 8.64893, y: 20.8267))
        p.addLine(to: CGPoint(x: 18.5723, y: 26.5542))
        p.addLine(to: CGPoint(x: 15.206, y: 28.4979))
        p.addCurve(to: CGPoint(x: 15.1505, y: 28.5173), control1: CGPoint(x: 15.1894, y: 28.5089), control2: CGPoint(x: 15.1703, y: 28.5155))
        p.addCurve(to: CGPoint(x: 15.0924, y: 28.5082), control1: CGPoint(x: 15.1307, y: 28.5191), control2: CGPoint(x: 15.1107, y: 28.516))
        p.addLine(to: CGPoint(x: 7.04046, y: 23.8557))
        p.addCurve(to: CGPoint(x: 3.55289, y: 19.3046), control1: CGPoint(x: 5.32135, y: 22.8601), control2: CGPoint(x: 4.06716, y: 21.2235))
        p.addCurve(to: CGPoint(x: 4.29707, y: 13.6194), control1: CGPoint(x: 3.03862, y: 17.3858), control2: CGPoint(x: 3.30624, y: 15.3413))
        p.closeSubpath()
        p.move(to: CGPoint(x: 31.955, y: 20.0556))
        p.addLine(to: CGPoint(x: 22.2312, y: 14.4411))
        p.addLine(to: CGPoint(x: 25.5976, y: 12.4981))
        p.addCurve(to: CGPoint(x: 25.6531, y: 12.4787), control1: CGPoint(x: 25.6142, y: 12.4872), control2: CGPoint(x: 25.6333, y: 12.4805))
        p.addCurve(to: CGPoint(x: 25.7111, y: 12.4879), control1: CGPoint(x: 25.6729, y: 12.4769), control2: CGPoint(x: 25.6928, y: 12.4801))
        p.addLine(to: CGPoint(x: 33.7631, y: 17.1364))
        p.addCurve(to: CGPoint(x: 36.6606, y: 20.1613), control1: CGPoint(x: 34.9967, y: 17.849), control2: CGPoint(x: 36.0017, y: 18.8982))
        p.addCurve(to: CGPoint(x: 37.4832, y: 24.2684), control1: CGPoint(x: 37.3194, y: 21.4244), control2: CGPoint(x: 37.6047, y: 22.849))
        p.addCurve(to: CGPoint(x: 35.9743, y: 28.1759), control1: CGPoint(x: 37.3617, y: 25.6878), control2: CGPoint(x: 36.8382, y: 27.0432))
        p.addCurve(to: CGPoint(x: 32.6047, y: 30.6641), control1: CGPoint(x: 35.1103, y: 29.3086), control2: CGPoint(x: 33.9415, y: 30.1717))
        p.addCurve(to: CGPoint(x: 32.6047, y: 30.3889), control1: CGPoint(x: 32.6047, y: 30.5947), control2: CGPoint(x: 32.6047, y: 30.4733))
        p.addLine(to: CGPoint(x: p.currentPoint.x, y: 21.188))
        p.addCurve(to: CGPoint(x: 32.4332, y: 20.5338), control1: CGPoint(x: 32.6066, y: 20.9586), control2: CGPoint(x: 32.5474, y: 20.7328))
        p.addCurve(to: CGPoint(x: 31.955, y: 20.0556), control1: CGPoint(x: 32.319, y: 20.3348), control2: CGPoint(x: 32.154, y: 20.1698))
        p.closeSubpath()
        p.move(to: CGPoint(x: 35.3055, y: 15.0128))
        p.addCurve(to: CGPoint(x: 35.069, y: 14.8717), control1: CGPoint(x: 35.2464, y: 14.9765), control2: CGPoint(x: 35.1431, y: 14.9142))
        p.addLine(to: CGPoint(x: 27.1045, y: 10.2712))
        p.addCurve(to: CGPoint(x: 26.4504, y: 10.0943), control1: CGPoint(x: 26.906, y: 10.1554), control2: CGPoint(x: 26.6803, y: 10.0943))
        p.addCurve(to: CGPoint(x: 25.7963, y: 10.2712), control1: CGPoint(x: 26.2206, y: 10.0943), control2: CGPoint(x: 25.9948, y: 10.1554))
        p.addLine(to: CGPoint(x: 16.0726, y: 15.8858))
        p.addLine(to: CGPoint(x: p.currentPoint.x, y: 11.9982))
        p.addCurve(to: CGPoint(x: 16.0837, y: 11.9405), control1: CGPoint(x: 16.0715, y: 11.9783), control2: CGPoint(x: 16.0753, y: 11.9585))
        p.addCurve(to: CGPoint(x: 16.1207, y: 11.8949), control1: CGPoint(x: 16.0921, y: 11.9225), control2: CGPoint(x: 16.1048, y: 11.9068))
        p.addLine(to: CGPoint(x: 24.1719, y: 7.25025))
        p.addCurve(to: CGPoint(x: 28.2383, y: 6.25482), control1: CGPoint(x: 25.4053, y: 6.53903), control2: CGPoint(x: 26.8158, y: 6.19376))
        p.addCurve(to: CGPoint(x: 32.2044, y: 7.59508), control1: CGPoint(x: 29.6608, y: 6.31589), control2: CGPoint(x: 31.0364, y: 6.78077))
        p.addCurve(to: CGPoint(x: 34.8334, y: 10.8531), control1: CGPoint(x: 33.3723, y: 8.40939), control2: CGPoint(x: 34.2842, y: 9.53945))
        p.addCurve(to: CGPoint(x: 35.3055, y: 15.0128), control1: CGPoint(x: 35.3826, y: 12.1667), control2: CGPoint(x: 35.5464, y: 13.6095))
        p.closeSubpath()
        p.move(to: CGPoint(x: 14.2424, y: 21.9419))
        p.addLine(to: CGPoint(x: 10.8752, y: 19.9981))
        p.addCurve(to: CGPoint(x: 10.8309, y: 19.9602), control1: CGPoint(x: 10.8576, y: 19.9893), control2: CGPoint(x: 10.8423, y: 19.9763))
        p.addCurve(to: CGPoint(x: 10.8098, y: 19.9058), control1: CGPoint(x: 10.8195, y: 19.9441), control2: CGPoint(x: 10.8122, y: 19.9254))
        p.addLine(to: CGPoint(x: p.currentPoint.x, y: 10.6071))
        p.addCurve(to: CGPoint(x: 11.9819, y: 6.58696), control1: CGPoint(x: 10.8107, y: 9.18295), control2: CGPoint(x: 11.2173, y: 7.78848))
        p.addCurve(to: CGPoint(x: 15.1275, y: 3.82264), control1: CGPoint(x: 12.7466, y: 5.38544), control2: CGPoint(x: 13.8377, y: 4.42659))
        p.addCurve(to: CGPoint(x: 19.2649, y: 3.1767), control1: CGPoint(x: 16.4173, y: 3.21869), control2: CGPoint(x: 17.8524, y: 2.99464))
        p.addCurve(to: CGPoint(x: 23.1034, y: 4.85067), control1: CGPoint(x: 20.6775, y: 3.35876), control2: CGPoint(x: 22.0089, y: 3.93941))
        p.addCurve(to: CGPoint(x: 22.8668, y: 4.98473), control1: CGPoint(x: 23.0427, y: 4.88379), control2: CGPoint(x: 22.937, y: 4.94215))
        p.addLine(to: CGPoint(x: 14.9024, y: 9.58517))
        p.addCurve(to: CGPoint(x: 14.4215, y: 10.0626), control1: CGPoint(x: 14.7025, y: 9.69878), control2: CGPoint(x: 14.5366, y: 9.86356))
        p.addCurve(to: CGPoint(x: 14.2479, y: 10.7175), control1: CGPoint(x: 14.3065, y: 10.2616), control2: CGPoint(x: 14.2466, y: 10.4877))
        p.addLine(to: CGPoint(x: 14.2424, y: 21.9419))
        p.closeSubpath()
        p.move(to: CGPoint(x: 16.071, y: 17.9991))
        p.addLine(to: CGPoint(x: 20.4018, y: 15.4978))
        p.addLine(to: CGPoint(x: 24.7325, y: 17.9975))
        p.addLine(to: CGPoint(x: p.currentPoint.x, y: 22.9985))
        p.addLine(to: CGPoint(x: 20.4018, y: 25.4983))
        p.addLine(to: CGPoint(x: 16.071, y: 22.9985))
        p.addLine(to: CGPoint(x: p.currentPoint.x, y: 17.9991))
        p.closeSubpath()
        return p
    }()
    private static let antigravity: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 89.6992, y: 93.695))
        p.addCurve(to: CGPoint(x: 94.9492, y: 88.445), control1: CGPoint(x: 94.3659, y: 97.195), control2: CGPoint(x: 101.366, y: 94.8617))
        p.addCurve(to: CGPoint(x: 55.8659, y: 18.445), control1: CGPoint(x: 75.6992, y: 69.7783), control2: CGPoint(x: 79.7825, y: 18.445))
        p.addCurve(to: CGPoint(x: 16.7825, y: 88.445), control1: CGPoint(x: 31.9492, y: 18.445), control2: CGPoint(x: 36.0325, y: 69.7783))
        p.addCurve(to: CGPoint(x: 22.0325, y: 93.695), control1: CGPoint(x: 9.78251, y: 95.445), control2: CGPoint(x: 17.3658, y: 97.195))
        p.addCurve(to: CGPoint(x: 55.8659, y: 59.8617), control1: CGPoint(x: 40.1159, y: 81.445), control2: CGPoint(x: 38.9492, y: 59.8617))
        p.addCurve(to: CGPoint(x: 89.6992, y: 93.695), control1: CGPoint(x: 72.7825, y: 59.8617), control2: CGPoint(x: 71.6159, y: 81.445))
        p.closeSubpath()
        return p
    }()
}
