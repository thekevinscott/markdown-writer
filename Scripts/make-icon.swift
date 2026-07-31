// Renders AppIcon.icns: warm paper squircle with the Markdown "M↓" mark in
// the app's terracotta accent. Rerun after design changes:
//   swift Scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let palettePaperTop = NSColor(srgbRed: 0xFD / 255, green: 0xFC / 255, blue: 0xFA / 255, alpha: 1)
let palettePaperBottom = NSColor(srgbRed: 0xF1 / 255, green: 0xEE / 255, blue: 0xE7 / 255, alpha: 1)
let paletteBorder = NSColor(srgbRed: 0xE2 / 255, green: 0xDD / 255, blue: 0xD2 / 255, alpha: 1)
let paletteAccent = NSColor(srgbRed: 0xB0 / 255, green: 0x53 / 255, blue: 0x2F / 255, alpha: 1)

func draw(into pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let size = CGFloat(pixels)
    // Apple's icon grid: content inset ~10% per side, radius ~18% of canvas.
    let plate = NSRect(x: size * 0.098, y: size * 0.098,
                       width: size * 0.804, height: size * 0.804)
    let radius = size * 0.18
    let squircle = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)
    NSGradient(starting: palettePaperTop, ending: palettePaperBottom)?
        .draw(in: squircle, angle: -90)
    paletteBorder.setStroke()
    squircle.lineWidth = max(1, size / 512)
    squircle.stroke()

    let font = NSFont.systemFont(ofSize: size * 0.40, weight: .heavy)
    let mark = NSAttributedString(string: "M↓", attributes: [
        .font: font,
        .foregroundColor: paletteAccent,
        .kern: size * 0.01
    ])
    let bounds = mark.size()
    // Center on the cap height, not the em box, so the mark sits optically.
    let baseline = plate.midY - font.capHeight / 2
    mark.draw(at: NSPoint(x: plate.midX - bounds.width / 2,
                          y: baseline - (font.ascender - font.capHeight) - font.descender / 2))
    return rep
}

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.icns"
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppIcon-\(ProcessInfo.processInfo.processIdentifier).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = draw(into: base * scale).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try iconutil.run()
iconutil.waitUntilExit()
try FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed")
}
print("Wrote \(output)")
