import Cocoa

// MightyMouse app icon: a dark rounded-square (squircle) background with a white
// mouse silhouette; the scroll wheel and a 4-directional arrow cross are carved
// out as negative space so the dark background shows through.

// White mouse silhouette with transparent negative-space cutouts.
func drawGlyph(size S: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: S, height: S))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    let bw = S * 0.46
    let bh = S * 0.70
    let body = NSRect(x: (S - bw) / 2, y: (S - bh) / 2, width: bw, height: bh)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: body, xRadius: bw / 2, yRadius: bw / 2).fill()

    ctx.setBlendMode(.destinationOut)

    // Scroll wheel: short rounded bar near the top.
    let ww = S * 0.045, wh = S * 0.11
    let wheel = NSRect(x: S/2 - ww/2, y: body.maxY - wh - S * 0.075, width: ww, height: wh)
    NSBezierPath(roundedRect: wheel, xRadius: ww/2, yRadius: ww/2).fill()

    // 4-directional arrow cross carved into the lower half.
    let conf = NSImage.SymbolConfiguration(pointSize: S * 0.5, weight: .bold)
    if let arrows = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
                            accessibilityDescription: nil)?
        .withSymbolConfiguration(conf) {
        let aw = bw * 0.72
        let ah = arrows.size.height / arrows.size.width * aw
        arrows.draw(in: NSRect(x: S/2 - aw/2, y: body.minY + bh * 0.34 - ah/2, width: aw, height: ah),
                    from: .zero, operation: .destinationOut, fraction: 1.0)
    }

    ctx.setBlendMode(.normal)
    img.unlockFocus()
    return img
}

// App icon: dark squircle background + the white glyph on top (holes reveal the background).
func drawIcon(size S: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: S, height: S))
    img.lockFocus()

    let inset = S * 0.06
    let bg = NSRect(x: inset, y: inset, width: S - 2*inset, height: S - 2*inset)
    let radius = bg.width * 0.225
    NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
    NSBezierPath(roundedRect: bg, xRadius: radius, yRadius: radius).fill()

    drawGlyph(size: S).draw(in: NSRect(x: 0, y: 0, width: S, height: S))

    img.unlockFocus()
    return img
}

func savePNG(_ image: NSImage, to url: URL, pixels: Int) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])!.write(to: url)
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "AppIcon.iconset")
try? fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let specs: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

let master = drawIcon(size: 1024)
for (px, name) in specs {
    savePNG(master, to: iconset.appendingPathComponent("\(name).png"), pixels: px)
}
savePNG(master, to: URL(fileURLWithPath: "icon-preview.png"), pixels: 512)
print("iconset written")
