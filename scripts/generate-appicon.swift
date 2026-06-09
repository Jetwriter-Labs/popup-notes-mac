import AppKit

// Renders the app icon — an SF Symbol "note.text" glyph on an amber squircle —
// at every macOS size, and writes the PNGs + Contents.json into the given
// .appiconset directory. Re-run to regenerate.
//
// Usage: swift scripts/generate-appicon.swift [path-to-AppIcon.appiconset]

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "PopupNotes/PopupNotes/Assets.xcassets/AppIcon.appiconset"

func renderIcon(px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size) // 1 point == 1 pixel

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: size * 0.2237, yRadius: size * 0.2237)
    squircle.addClip()
    NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.80, blue: 0.30, alpha: 1.0),
        NSColor(calibratedRed: 0.97, green: 0.56, blue: 0.11, alpha: 1.0),
    ])!.draw(in: rect, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(hierarchicalColor: .white))
    if let glyph = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let gs = glyph.size
        let scale = (size * 0.5) / max(gs.width, gs.height)
        let w = gs.width * scale, h = gs.height * scale
        glyph.draw(in: NSRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for px in [16, 32, 64, 128, 256, 512, 1024] {
    try! renderIcon(px: px).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(px).png"))
    print("wrote icon_\(px).png")
}

let contents = """
{
  "images" : [
    { "idiom" : "mac", "size" : "16x16", "scale" : "1x", "filename" : "icon_16.png" },
    { "idiom" : "mac", "size" : "16x16", "scale" : "2x", "filename" : "icon_32.png" },
    { "idiom" : "mac", "size" : "32x32", "scale" : "1x", "filename" : "icon_32.png" },
    { "idiom" : "mac", "size" : "32x32", "scale" : "2x", "filename" : "icon_64.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "1x", "filename" : "icon_128.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "2x", "filename" : "icon_256.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "1x", "filename" : "icon_256.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "2x", "filename" : "icon_512.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "1x", "filename" : "icon_512.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "2x", "filename" : "icon_1024.png" }
  ],
  "info" : { "version" : 1, "author" : "popupnotes-generator" }
}
"""
try! contents.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
print("wrote Contents.json")
