// Renders the Keyflip app icon.
// Run: make icon   (or: swift Tools/AppIcon/generate.swift)
//
// Two outputs from one geometry, so they cannot drift apart:
//   App/Keyflip.icns              — the flat icon, and the pre-26 fallback
//   App/Keyflip.icon/Assets/*.png — the macOS 26 Liquid Glass layers
//
// The mark quotes the status item glyph (SF Symbol arrow.left.arrow.right, see
// StatusItemController) sitting on a keycap.

import AppKit
import CoreGraphics

_ = NSApplication.shared

let appDir = URL(fileURLWithPath: "App")
let glassDir = appDir.appendingPathComponent("Keyflip.icon/Assets")

// MARK: - Apple continuous-corner rounded rect (squircle)

func squircle(_ rect: CGRect, radius r0: CGFloat) -> CGPath {
    let r = min(r0, min(rect.width, rect.height) / (2 * 1.528665))
    let p = CGMutablePath()
    let minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
    func pt(_ c: CGPoint, _ u: CGVector, _ v: CGVector, _ a: CGFloat, _ b: CGFloat) -> CGPoint {
        CGPoint(x: c.x + (u.dx * a + v.dx * b) * r, y: c.y + (u.dy * a + v.dy * b) * r)
    }
    func corner(_ c: CGPoint, _ u: CGVector, _ v: CGVector) {
        p.addCurve(to: pt(c, u, v, 0.630493, 0.130447),
                   control1: pt(c, u, v, 1.088492, 0), control2: pt(c, u, v, 0.868407, 0))
        p.addCurve(to: pt(c, u, v, 0.130447, 0.630493),
                   control1: pt(c, u, v, 0.451592, 0.198005), control2: pt(c, u, v, 0.198005, 0.451592))
        p.addCurve(to: pt(c, u, v, 0, 1.528665),
                   control1: pt(c, u, v, 0, 0.868407), control2: pt(c, u, v, 0, 1.088492))
    }
    let d = 1.528665 * r
    let TL = CGPoint(x: minX, y: minY), TR = CGPoint(x: maxX, y: minY)
    let BR = CGPoint(x: maxX, y: maxY), BL = CGPoint(x: minX, y: maxY)
    p.move(to: CGPoint(x: minX + d, y: minY))
    p.addLine(to: CGPoint(x: maxX - d, y: minY))
    corner(TR, CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1))
    p.addLine(to: CGPoint(x: maxX, y: maxY - d))
    corner(BR, CGVector(dx: 0, dy: -1), CGVector(dx: -1, dy: 0))
    p.addLine(to: CGPoint(x: minX + d, y: maxY))
    corner(BL, CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: -1))
    p.addLine(to: CGPoint(x: minX, y: minY + d))
    corner(TL, CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 0))
    p.closeSubpath()
    return p
}

// MARK: - Drawing helpers

func hex(_ s: String, _ a: CGFloat = 1) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: s.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
                   green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: a)
}

func gradient(_ colors: [NSColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    return CGGradient(colorsSpace: space,
                      colors: colors.map { $0.cgColor } as CFArray,
                      locations: locations)!
}

/// Fills `path` with a linear gradient running from unit point `from` to `to` in the path's bounding box.
func fillGradient(_ ctx: CGContext, _ path: CGPath, _ colors: [NSColor],
                  from: CGPoint = CGPoint(x: 0.5, y: 1), to: CGPoint = CGPoint(x: 0.5, y: 0),
                  locations: [CGFloat]? = nil) {
    let b = path.boundingBox
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient(colors, locations),
        start: CGPoint(x: b.minX + b.width * from.x, y: b.minY + b.height * from.y),
        end: CGPoint(x: b.minX + b.width * to.x, y: b.minY + b.height * to.y),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func shadow(_ ctx: CGContext, blur: CGFloat, dy: CGFloat, color: NSColor, _ body: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -dy), blur: blur, color: color.cgColor)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    body()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

/// The app's menu bar glyph, as an image to be used as a fill mask.
func swapSymbol(width: CGFloat, weight: NSFont.Weight = .semibold) -> NSImage? {
    let cfg = NSImage.SymbolConfiguration(pointSize: width, weight: weight)
    return NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg)
}

func drawSymbol(_ ctx: CGContext, _ image: NSImage, color: NSColor, center: CGPoint, targetWidth: CGFloat) {
    let size = image.size
    let scale = targetWidth / size.width
    let w = size.width * scale, h = size.height * scale
    let rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    ctx.saveGState()
    ctx.clip(to: rect, mask: cg)
    ctx.setFillColor(color.cgColor)
    ctx.fill(rect)
    ctx.restoreGState()
}

/// A physical keycap: body + inset top face.
func keycap(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, body: [NSColor], face: [NSColor]) {
    let bodyPath = squircle(rect, radius: radius)
    shadow(ctx, blur: rect.width * 0.14, dy: rect.width * 0.05, color: hex("000000", 0.38)) {
        fillGradient(ctx, bodyPath, body)
    }
    let inset = rect.width * 0.085
    let faceRect = CGRect(x: rect.minX + inset, y: rect.minY + inset * 1.5,
                          width: rect.width - inset * 2, height: rect.height - inset * 2.2)
    fillGradient(ctx, squircle(faceRect, radius: radius * 0.78), face)
}

// MARK: - Canvas

let canvas: CGFloat = 1024
let plateRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let plateRadius: CGFloat = 824 * 0.2237
let capRect = CGRect(x: 272, y: 268, width: 480, height: 480)
let capRadius: CGFloat = 112
let glyphCenter = CGPoint(x: 512, y: 514)
let glyphWidth: CGFloat = 286

func makeContext(_ size: CGFloat) -> CGContext {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                            | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    return ctx
}

/// Ground plate: outer shadow, gradient fill, top sheen, hairline rim.
func plate(_ ctx: CGContext, _ colors: [NSColor], sheen: CGFloat = 0.14) {
    let path = squircle(plateRect, radius: plateRadius)
    shadow(ctx, blur: 34, dy: 14, color: hex("000000", 0.30)) {
        fillGradient(ctx, path, colors)
    }
    // top sheen
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([hex("FFFFFF", sheen), hex("FFFFFF", 0)]),
        start: CGPoint(x: 0, y: plateRect.maxY),
        end: CGPoint(x: 0, y: plateRect.midY + 60),
        options: [])
    ctx.restoreGState()
    // rim
    ctx.saveGState()
    ctx.addPath(squircle(plateRect.insetBy(dx: 1.25, dy: 1.25), radius: plateRadius))
    ctx.setStrokeColor(hex("FFFFFF", 0.18).cgColor)
    ctx.setLineWidth(2.5)
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Output

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

func scaled(_ image: CGImage, to side: Int) -> CGImage {
    let ctx = makeContext(CGFloat(side))
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return ctx.makeImage()!
}

func render(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = makeContext(canvas)
    draw(ctx)
    return ctx.makeImage()!
}

func makeICNS(_ master: CGImage, to url: URL) {
    let set = url.deletingLastPathComponent().appendingPathComponent("Keyflip.iconset")
    try? FileManager.default.removeItem(at: set)
    try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    let plan: [(Int, String)] = [
        (16, "icon_16x16"), (32, "icon_16x16@2x"),
        (32, "icon_32x32"), (64, "icon_32x32@2x"),
        (128, "icon_128x128"), (256, "icon_128x128@2x"),
        (256, "icon_256x256"), (512, "icon_256x256@2x"),
        (512, "icon_512x512"), (1024, "icon_512x512@2x"),
    ]
    for (px, file) in plan {
        let img = px == 1024 ? master : scaled(master, to: px)
        writePNG(img, to: set.appendingPathComponent("\(file).png"))
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    p.arguments = ["-c", "icns", set.path, "-o", url.path]
    try? p.run()
    p.waitUntilExit()
    try? FileManager.default.removeItem(at: set)
}

// The flat icon: keycap and glyph on a cyan-to-blue ground.
let icns = appDir.appendingPathComponent("Keyflip.icns")
makeICNS(render { ctx in
    plate(ctx, [hex("2DD4E8"), hex("2563EB")])
    keycap(ctx, capRect, radius: capRadius,
           body: [hex("FFFFFF"), hex("C6CEDF")],
           face: [hex("FFFFFF"), hex("EBEFF7")])
    if let sym = swapSymbol(width: 300) {
        drawSymbol(ctx, sym, color: hex("1B49B8"), center: glyphCenter, targetWidth: glyphWidth)
    }
}, to: icns)
print("wrote \(icns.path)")

// The Liquid Glass layers (macOS 26 / Icon Composer). Icon Composer supplies the
// container shape, the shadow and the glass material, so these carry no plate and
// no baked shadow — only flat artwork on transparency, on the same 1024 grid.
// Layer order and grouping live in App/Keyflip.icon/icon.json.
func emit(_ name: String, _ draw: (CGContext) -> Void) {
    writePNG(render(draw), to: glassDir.appendingPathComponent("\(name).png"))
}

// The glass material lightens and desaturates whatever it is given, so a deeper
// ground is needed to land on the same blue the .icns master shows.
emit("BackgroundDeep") { ctx in
    fillGradient(ctx, CGPath(rect: CGRect(x: 0, y: 0, width: canvas, height: canvas), transform: nil),
                 [hex("00B2D6"), hex("1637C4")])
}
emit("Keycap") { ctx in
    fillGradient(ctx, squircle(capRect, radius: capRadius), [hex("FFFFFF"), hex("F2F5FB")])
}
emit("Glyph") { ctx in
    if let sym = swapSymbol(width: 300) {
        drawSymbol(ctx, sym, color: hex("1B49B8"), center: glyphCenter, targetWidth: glyphWidth)
    }
}
print("wrote \(glassDir.path)")
