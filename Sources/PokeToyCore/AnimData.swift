import Foundation

/// One animation from a SpriteCollab `AnimData.xml`, with `CopyOf` already resolved.
public struct AnimInfo: Equatable, Sendable {
    public let name: String
    public let frameWidth: Int
    public let frameHeight: Int
    /// Per-frame durations in 1/60 s ticks.
    public let durations: [Int]
    /// The animation whose `<sourceName>-Anim.png` holds the pixels (differs from `name` for `CopyOf` entries).
    public let sourceName: String

    public init(name: String, frameWidth: Int, frameHeight: Int, durations: [Int], sourceName: String) {
        self.name = name
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.durations = durations
        self.sourceName = sourceName
    }
}

public enum AnimDataError: Error {
    case malformed(String)
}

public struct AnimData: Sendable {
    public let anims: [String: AnimInfo]

    public init(xml: Data) throws {
        let delegate = AnimDataParser()
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        guard parser.parse() else {
            throw AnimDataError.malformed(parser.parserError?.localizedDescription ?? "unknown XML error")
        }
        let byName = Dictionary(delegate.raws.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [String: AnimInfo] = [:]
        for raw in delegate.raws {
            var target = raw
            var hops = 0
            while let copy = target.copyOf, hops < 10, let next = byName[copy] {
                target = next
                hops += 1
            }
            guard target.copyOf == nil, let width = target.width, let height = target.height,
                  width > 0, height > 0, !target.durations.isEmpty else { continue }
            result[raw.name] = AnimInfo(name: raw.name, frameWidth: width, frameHeight: height,
                                        durations: target.durations, sourceName: target.name)
        }
        guard !result.isEmpty else { throw AnimDataError.malformed("no usable animations") }
        anims = result
    }

    /// The first animation in `candidates` that this Pokémon has.
    public func resolve(_ candidates: [String]) -> AnimInfo? {
        candidates.lazy.compactMap { anims[$0] }.first
    }
}

private final class AnimDataParser: NSObject, XMLParserDelegate {
    struct Raw {
        var name = ""
        var width: Int?
        var height: Int?
        var durations: [Int] = []
        var copyOf: String?
    }

    var raws: [Raw] = []
    private var current: Raw?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "Anim" { current = Raw() }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "Name": current?.name = value
        case "FrameWidth": current?.width = Int(value)
        case "FrameHeight": current?.height = Int(value)
        case "Duration": if let duration = Int(value) { current?.durations.append(duration) }
        case "CopyOf": current?.copyOf = value
        case "Anim":
            if let anim = current, !anim.name.isEmpty { raws.append(anim) }
            current = nil
        default: break
        }
        text = ""
    }
}
