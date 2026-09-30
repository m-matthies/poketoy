import CoreGraphics
import Foundation
import ImageIO
@testable import PokeToyCore

/// Builds an RGBA image; `opaquePixels` are (x, y) with y = 0 at the top.
func makeSheet(width: Int, height: Int, opaquePixels: [(Int, Int)]) -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for (x, y) in opaquePixels {
        let i = (y * width + x) * 4
        bytes[i] = 255; bytes[i + 1] = 0; bytes[i + 2] = 0; bytes[i + 3] = 255
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

struct TestAnim {
    var name: String
    var width = 4
    var height = 4
    var durations = [2, 4]
    var copyOf: String? = nil
}

func animDataXML(_ anims: [TestAnim]) -> String {
    let body = anims.map { anim -> String in
        if let copy = anim.copyOf {
            return "<Anim><Name>\(anim.name)</Name><CopyOf>\(copy)</CopyOf></Anim>"
        }
        let durations = anim.durations.map { "<Duration>\($0)</Duration>" }.joined()
        return "<Anim><Name>\(anim.name)</Name><FrameWidth>\(anim.width)</FrameWidth>"
            + "<FrameHeight>\(anim.height)</FrameHeight><Durations>\(durations)</Durations></Anim>"
    }.joined(separator: "\n")
    return "<?xml version=\"1.0\" ?><AnimData><ShadowSize>1</ShadowSize><Anims>\(body)</Anims></AnimData>"
}

/// Writes AnimData.xml plus an 8-row sheet for every non-copy anim (one opaque pixel at the bottom-center of each frame).
func writeSpriteDirectory(at dir: URL, anims: [TestAnim]) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data(animDataXML(anims).utf8).write(to: dir.appendingPathComponent("AnimData.xml"))
    for anim in anims where anim.copyOf == nil {
        let columns = anim.durations.count
        var pixels: [(Int, Int)] = []
        for row in 0..<8 {
            for column in 0..<columns {
                pixels.append((column * anim.width + anim.width / 2, row * anim.height + anim.height - 1))
            }
        }
        let sheet = makeSheet(width: columns * anim.width, height: 8 * anim.height, opaquePixels: pixels)
        try writePNG(sheet, to: dir.appendingPathComponent("\(anim.name)-Anim.png"))
    }
}

func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("PokeToyTests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - Playground helpers

enum TestWorld {
    static let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                   visibleFrame: CGRect(x: 0, y: 50, width: 1000, height: 725))
    static let floor = Surface(id: -1, minX: 0, maxX: 1000, y: 50, kind: .floor)
    static let shelf = Surface(id: 7, minX: 300, maxX: 600, y: 250, kind: .window)
    static let floorOnly = World(screens: [screen], surfaces: [floor])
    static let withShelf = World(screens: [screen], surfaces: [floor, shelf])
}

let farAway = CGPoint(x: -5000, y: -5000)

/// Ticks the playground for `seconds` at 60 Hz and returns every event.
@discardableResult
func play(_ playground: inout Playground, seconds: Double, world: World = TestWorld.floorOnly,
          cursor: CGPoint = farAway, mode: CursorMode = .off) -> [PlaygroundEvent] {
    var events: [PlaygroundEvent] = []
    for _ in 0..<Int((seconds * 60).rounded()) {
        events += playground.tick(dt: 1.0 / 60, world: world, cursor: cursor, cursorMode: mode)
    }
    return events
}

/// Ticks until `condition` holds (checked after every tick, at most `seconds`).
@discardableResult
func playUntil(_ playground: inout Playground, seconds: Double, world: World = TestWorld.floorOnly,
               cursor: CGPoint = farAway, mode: CursorMode = .off,
               _ condition: (Playground, [PlaygroundEvent]) -> Bool) -> (met: Bool, events: [PlaygroundEvent]) {
    var events: [PlaygroundEvent] = []
    for _ in 0..<Int((seconds * 60).rounded()) {
        events += playground.tick(dt: 1.0 / 60, world: world, cursor: cursor, cursorMode: mode)
        if condition(playground, events) { return (true, events) }
    }
    return (false, events)
}

/// A playground with one own pet standing on the floor at each x.
func makePlayground(_ xs: [CGFloat], seed: UInt64 = 1, scale: CGFloat = 1,
                    world: World = TestWorld.floorOnly) -> (Playground, [UUID]) {
    var playground = Playground(seed: seed, scale: scale)
    let ids = xs.map { playground.addPet(metrics: .uniform(), at: CGPoint(x: $0, y: TestWorld.floor.y + 1)) }
    play(&playground, seconds: 0.05, world: world)
    return (playground, ids)
}
