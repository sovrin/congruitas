// Draws the app icon and the menu bar icons and writes them into Assets.xcassets.
// Run from the repo root: swift tools/make-icon.swift
import AppKit

let assets = URL(fileURLWithPath: "congruitas/Assets.xcassets")

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: 1)
}

func rounded(_ rect: NSRect, _ radius: Double) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// Runs `draw` with the origin moved to (x, y) and rotated by `degrees`.
func placed(_ x: Double, _ y: Double, rotated degrees: Double = 0, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: x, yBy: y)
    transform.rotate(byDegrees: degrees)
    transform.concat()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

/// Erases whatever `draw` fills, so shapes keep a gap between them in one-color images.
func erasing(_ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current?.compositingOperation = .clear
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

/// The ".*" mark: a dot and a three-bar asterisk centered at (x, y).
func regexMark(x: Double, y: Double, size: Double) {
    NSBezierPath(ovalIn: NSRect(x: x - size * 0.317, y: y - size * 0.256, width: size * 0.2, height: size * 0.2)).fill()
    for angle in [90.0, 30, 150] {
        placed(x + size * 0.089, y + size * 0.106, rotated: angle) {
            rounded(NSRect(x: -size * 0.228, y: -size * 0.058, width: size * 0.456, height: size * 0.117), size * 0.058).fill()
        }
    }
}

/// Draws on a `canvas`-sized square, scaled to `pixels`.
func png(_ pixels: Int, canvas: Double, _ draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = NSAffineTransform()
    scale.scale(by: Double(pixels) / canvas)
    scale.concat()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// The glyph on an 18pt grid: a folder with ".*" cut out of it, for folders sorted by regex rules.
func folderGlyph() {
    // The tab reaches down into the body's straight edge, so their round corners leave no notch.
    rounded(NSRect(x: 1, y: 9, width: 7, height: 7), 1.6).fill()
    rounded(NSRect(x: 1, y: 2, width: 16, height: 12), 2.4).fill()
    erasing { regexMark(x: 9, y: 7.8, size: 9.6) }
}

// MARK: App icon (1024 canvas), the same tile as the panel header

func appIcon() {
    // Body: Apple's macOS grid, an 824pt tile with a soft drop shadow, indigo to purple like the panel header.
    let body = rounded(NSRect(x: 100, y: 100, width: 824, height: 824), 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.set()
    color(0x6A50DA).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0x5856D6), color(0xAF52DE)])!.draw(in: body, angle: -45)
    NSGradient(colorsAndLocations: (.white.withAlphaComponent(0.18), 0), (.white.withAlphaComponent(0), 0.5))!
        .draw(in: body, angle: -90)

    // The glyph in white, scaled up. Drawn in its own layer, so its ".*" cuts through to the tile.
    NSGraphicsContext.saveGraphicsState()
    let lift = NSShadow()
    lift.shadowBlurRadius = 24
    lift.shadowOffset = NSSize(width: 0, height: -10)
    lift.shadowColor = .black.withAlphaComponent(0.22)
    lift.set()
    let cg = NSGraphicsContext.current!.cgContext
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    let scale = 34.0
    let transform = NSAffineTransform()
    transform.translateX(by: 512 - 9 * scale, yBy: 512 - 9 * scale)
    transform.scale(by: scale)
    transform.concat()
    NSColor.white.setFill()
    folderGlyph()
    cg.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: Menu bar icon (18pt template: black on clear, macOS tints it)

func menuBarIcon(marked: Bool) {
    NSColor.black.setFill()
    folderGlyph()
    // Files are marked for the Trash: a dot top right, cut free of the folder.
    if marked {
        let dot = NSRect(x: 13.4, y: 13.4, width: 4.4, height: 4.4)
        erasing { NSBezierPath(ovalIn: dot.insetBy(dx: -1.2, dy: -1.2)).fill() }
        NSBezierPath(ovalIn: dot).fill()
    }
}

// MARK: Write

func write(_ contents: [String: Any], to set: URL) throws {
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: set.appending(path: "Contents.json"))
}

let info = ["author": "xcode", "version": 1] as [String: Any]

let appIconSet = assets.appending(path: "AppIcon.appiconset")
var icons: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let file = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(points * scale, canvas: 1024, appIcon).write(to: appIconSet.appending(path: file))
        icons.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)", "filename": file])
    }
}
try write(["images": icons, "info": info], to: appIconSet)

for (name, marked) in [("MenuBarIcon", false), ("MenuBarIconMarked", true)] {
    let set = assets.appending(path: "\(name).imageset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    for scale in [1, 2] {
        let file = "\(name)\(scale == 2 ? "@2x" : "").png"
        try png(18 * scale, canvas: 18) { menuBarIcon(marked: marked) }.write(to: set.appending(path: file))
        images.append(["idiom": "universal", "scale": "\(scale)x", "filename": file])
    }
    try write(["images": images, "info": info, "properties": ["template-rendering-intent": "template"]], to: set)
}
print("Wrote the app icon and menu bar icons to \(assets.path)")
