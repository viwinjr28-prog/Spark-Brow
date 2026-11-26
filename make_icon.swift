import Cocoa

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func renderIcon(px: Int, path: String) {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let pad = s * 0.06
    let card = rect.insetBy(dx: pad, dy: pad)
    let r = card.width * 0.24
    let bp = NSBezierPath(roundedRect: card, xRadius: r, yRadius: r)
    let grad = NSGradient(colors: [
        NSColor(calibratedRed: 0.49, green: 0.23, blue: 0.93, alpha: 1.0),
        NSColor(calibratedRed: 0.14, green: 0.18, blue: 0.48, alpha: 1.0),
        NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.12, alpha: 1.0)
    ])!
    grad.draw(in: bp, angle: -55)

    // Specular rim
    NSColor.white.withAlphaComponent(0.38).setStroke()
    bp.lineWidth = max(1.0, s * 0.015)
    bp.stroke()

    // 4-point Spark star
    let cx = s * 0.5, cy = s * 0.5, outer = s * 0.28, inner = s * 0.09
    let star = NSBezierPath()
    for i in 0..<8 {
        let ang = CGFloat(i) * .pi / 4.0
        let rad = (i % 2 == 0) ? outer : inner
        let pt = NSPoint(x: cx + cos(ang) * rad, y: cy + sin(ang) * rad)
        if i == 0 { star.move(to: pt) } else { star.line(to: pt) }
    }
    star.close()
    NSColor.white.withAlphaComponent(0.95).setFill()
    star.fill()

    img.unlockFocus()
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

for sz in [16, 32, 128, 256, 512] {
    renderIcon(px: sz, path: "\(outDir)/icon_\(sz)x\(sz).png")
    renderIcon(px: sz * 2, path: "\(outDir)/icon_\(sz)x\(sz)@2x.png")
}
