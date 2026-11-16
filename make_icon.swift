// make_icon.swift — 生成应用图标(独立运行:swift make_icon.swift <输出目录>)
// 依据原版 sidedock.icns / menubar.png 视觉证据:蓝→青对角渐变圆角方块 + 白色粗体 "S"
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size = 1024

let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

let inset: CGFloat = 90
let rect = CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
let colors = [CGColor(red: 0.36, green: 0.62, blue: 0.94, alpha: 1),   // #5B9FE0
              CGColor(red: 0.25, green: 0.71, blue: 0.94, alpha: 1)] as CFArray  // #40B5F0
let grad = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1])!
let path = CGPath(roundedRect: rect, cornerWidth: 190, cornerHeight: 190, transform: nil)
ctx.addPath(path)
ctx.saveGState()
ctx.clip()
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(size)),
                        end: CGPoint(x: CGFloat(size), y: 0), options: [])
ctx.restoreGState()

// 白色粗体 "S"(用系统字体直接绘制)
let font = NSFont.systemFont(ofSize: 560, weight: .bold)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
]
let str = NSAttributedString(string: "S", attributes: attrs)
let bound = str.boundingRect(with: NSSize(width: 900, height: 900), options: [.usesLineFragmentOrigin])
let s = str.size()
let textTopLeftX = rect.midX - s.width / 2
let textTopLeftY = rect.midY + bound.height / 2 - (bound.height - s.height) / 2
str.draw(at: NSPoint(x: textTopLeftX, y: textTopLeftY))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let png = rep.representation(using: .png, properties: [:])!
let outURL = URL(fileURLWithPath: outDir).appendingPathComponent("icon_1024.png")
try! png.write(to: outURL)
print("wrote \(outURL.path)")
