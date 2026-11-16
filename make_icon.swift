// make_icon.swift — 生成应用图标(独立运行:swift make_icon.swift <输出目录>)
// 玻璃主题图标(与 Open Design 设计稿 04 节一致):
//   macOS 风格超椭圆圆角方(squircle,n≈5)+ 品牌蓝→靛对角渐变 + 顶部高光/底部纵深;
//   图形 = 半透明玻璃面板(三条坞位横条)+ 右缘白色把手,即 SideDock 的形态自述。
// 直接渲染全套 iconset 各尺寸(小尺寸自动简化为两条横条),不经位图缩放,边缘更锐。
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// MARK: - 颜色

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func gradient(_ space: CGColorSpace, _ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space,
               colors: stops.map(\.1) as CFArray,
               locations: stops.map(\.0))!
}

// MARK: - 超椭圆圆角方(macOS 风格 squircle)

/// Lamé 超椭圆 |x/a|^n + |y/b|^n = 1;n=2 圆,n≈5 接近 macOS 图标的连续曲率圆角方
func superellipsePath(in rect: CGRect, n: Double, samples: Int = 220) -> CGPath {
    let a = Double(rect.width) / 2, b = Double(rect.height) / 2
    let cx = Double(rect.midX), cy = Double(rect.midY)
    let exp = 2.0 / n
    var points: [CGPoint] = []
    points.reserveCapacity(samples)
    for i in 0..<samples {
        let t = Double(i) / Double(samples) * 2 * Double.pi
        let c = cos(t), s = sin(t)
        let x = cx + a * copysign(pow(abs(c), exp), c)
        let y = cy + b * copysign(pow(abs(s), exp), s)
        points.append(CGPoint(x: x, y: y))
    }
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path
}

// MARK: - 绘制

func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let k = s / 1024   // 设计稿 1024 画布的缩放系数
    let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: rgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let inset = k * 90
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = superellipsePath(in: rect, n: 5)

    // ---- 底板:品牌蓝→靛对角渐变(设计稿 135° #5B9FE0 → #2F7BFF 52% → #1E63D0)----
    ctx.addPath(shape)
    ctx.saveGState()
    ctx.clip()
    ctx.drawLinearGradient(
        gradient(rgb, [(0, color(0x5B9FE0)), (0.52, color(0x2F7BFF)), (1, color(0x1E63D0))]),
        start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // 顶部径向高光(82%, 94% 处白色 30%)
    ctx.drawRadialGradient(
        gradient(rgb, [(0, color(0xFFFFFF, 0.30)), (1, color(0xFFFFFF, 0))]),
        startCenter: CGPoint(x: s * 0.82, y: s * 0.94), startRadius: 0,
        endCenter: CGPoint(x: s * 0.82, y: s * 0.94), endRadius: s * 0.46, options: [])

    // 顶部斜向光泽
    ctx.drawLinearGradient(
        gradient(rgb, [(0, color(0xFFFFFF, 0.16)), (1, color(0xFFFFFF, 0))]),
        start: CGPoint(x: s * 0.20, y: s), end: CGPoint(x: s * 0.55, y: s * 0.52), options: [])

    // 底部纵深(深蓝内阴影感)
    ctx.drawLinearGradient(
        gradient(rgb, [(0, color(0x0A285A, 0.32)), (1, color(0x0A285A, 0))]),
        start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    ctx.restoreGState()

    // ---- 内上高光描边(玻璃厚度)----
    ctx.addPath(shape)
    ctx.setStrokeColor(color(0xFFFFFF, 0.35))
    ctx.setLineWidth(3 * k)
    ctx.strokePath()

    // ---- 图形(裁剪到底板内)----
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    let pane = CGRect(x: rect.minX + rect.width * 0.09,     // 画布 18% − 底板 inset 9%
                      y: rect.minY + rect.height * 0.24,
                      width: rect.width * 0.56,
                      height: rect.height * 0.52)
    let barX = rect.minX + rect.width * 0.71
    let barW = rect.width * 0.07
    let bar = CGRect(x: barX, y: pane.minY, width: barW, height: pane.height)

    // 把手竖条(右缘,白→冰蓝渐变 + 投影)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * k), blur: 14 * k,
                  color: color(0x082864, 0.35))
    ctx.addPath(roundedRectPath(bar, radius: barW / 2))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient(rgb, [(0, color(0xFFFFFF)), (1, color(0xDCEBFF))]),
        start: CGPoint(x: bar.midX, y: bar.maxY), end: CGPoint(x: bar.midX, y: bar.minY), options: [])
    ctx.restoreGState()

    // 玻璃面板(白色半透明 + 投影 + 白描边)
    let paneShape = superellipsePath(in: pane, n: 4)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * k), blur: 20 * k,
                  color: color(0x082864, 0.30))
    ctx.addPath(paneShape)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient(rgb, [(0, color(0xFFFFFF, 0.42)), (1, color(0xFFFFFF, 0.16))]),
        start: CGPoint(x: pane.minX, y: pane.maxY), end: CGPoint(x: pane.maxX, y: pane.minY), options: [])
    ctx.restoreGState()

    // 面板顶部光泽
    ctx.saveGState()
    ctx.addPath(paneShape)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient(rgb, [(0, color(0xFFFFFF, 0.25)), (1, color(0xFFFFFF, 0))]),
        start: CGPoint(x: pane.minX, y: pane.maxY), end: CGPoint(x: pane.minX, y: pane.midY), options: [])
    ctx.restoreGState()

    ctx.addPath(paneShape)
    ctx.setStrokeColor(color(0xFFFFFF, 0.55))
    ctx.setLineWidth(6 * k)
    ctx.strokePath()

    // 坞位横条(≥64px 三条,<64px 简化为两条)
    let rowCount = size >= 64 ? 3 : 2
    let inner = pane.insetBy(dx: pane.width * 0.12, dy: 0)
    let rowH = pane.height * 0.11
    let gap = pane.height * 0.09
    let blockH = CGFloat(rowCount) * rowH + CGFloat(rowCount - 1) * gap
    var rowY = pane.midY + blockH / 2 - rowH
    let rowWidths: [CGFloat] = [1, 0.72, 0.46]
    for i in 0..<rowCount {
        let w = inner.width * rowWidths[i]
        let row = CGRect(x: inner.minX, y: rowY, width: w, height: rowH)
        ctx.saveGState()
        if size >= 64 {
            ctx.setShadow(offset: CGSize(width: 0, height: -1.5 * k), blur: 2 * k,
                          color: color(0x143C8C, 0.25))
        }
        ctx.addPath(roundedRectPath(row, radius: rowH / 2))
        ctx.setFillColor(color(0xFFFFFF, 0.85))
        ctx.fillPath()
        ctx.restoreGState()
        rowY -= rowH + gap
    }

    ctx.restoreGState()   // 底板裁剪结束
    return ctx.makeImage()!
}

// MARK: - 输出(icon_1024 母版 + 全套 iconset)

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make_icon", code: 1)
    }
    try png.write(to: url)
}

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let iconsetDir = URL(fileURLWithPath: outDir).appendingPathComponent("icon.iconset")
try? fm.createDirectory(atPath: iconsetDir.path, withIntermediateDirectories: true)

// 母版
let master = drawIcon(size: 1024)
try writePNG(master, to: URL(fileURLWithPath: outDir).appendingPathComponent("icon_1024.png"))

// iconset(标准 10 个槽位,逐尺寸重绘,小尺寸自动简化)
let slots: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (px, name) in slots {
    let img = px == 1024 ? master : drawIcon(size: px)
    try writePNG(img, to: iconsetDir.appendingPathComponent(name))
}
print("wrote icon_1024.png + icon.iconset(\(slots.count) slots) in \(outDir)")
