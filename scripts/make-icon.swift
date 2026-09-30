// Usage: swift scripts/make-icon.swift <portrait.png> <output.iconset>
// Draws the pixel-art portrait, unsmoothed, on a rounded gradient tile at every macOS icon size.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let portrait = NSImage(contentsOfFile: arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <portrait.png> <output.iconset>\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let tile = CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    context.addPath(CGPath(roundedRect: tile, cornerWidth: tile.width * 0.22, cornerHeight: tile.width * 0.22, transform: nil))
    context.clip()
    let colors = [CGColor(red: 1.0, green: 0.87, blue: 0.4, alpha: 1), CGColor(red: 0.98, green: 0.6, blue: 0.2, alpha: 1)]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: .zero, options: [])
    context.interpolationQuality = .none
    context.draw(portrait, in: tile.insetBy(dx: tile.width * 0.1, dy: tile.height * 0.1))
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
    ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024),
]
for (name, size) in sizes {
    try render(size: size).write(to: output.appendingPathComponent("icon_\(name).png"))
}
