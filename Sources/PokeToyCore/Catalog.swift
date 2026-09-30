import Foundation

/// A Pokémon (or form) that has sprites on SpriteCollab.
public struct CatalogEntry: Hashable, Codable, Identifiable, Sendable {
    /// Path under `sprite/`, e.g. `0025` or `0025/0000/0001`.
    public let path: String
    public let displayName: String
    /// SpriteCollab marks the sprite set "Full" (`sprite_complete == 2`, ~35 animations).
    public let isComplete: Bool
    public var id: String { path }

    public init(path: String, displayName: String, isComplete: Bool = false) {
        self.path = path
        self.displayName = displayName
        self.isComplete = isComplete
    }
}

public enum Catalog {
    public static func parse(trackerJSON: Data) throws -> [CatalogEntry] {
        let root = try JSONDecoder().decode([String: TrackerNode].self, from: trackerJSON)
        var entries: [CatalogEntry] = []
        for (id, node) in root {
            let base = cleanName(node.name)
            collect(node, path: id, base: base, qualifiers: [], into: &entries)
        }
        return entries.sorted { $0.path < $1.path }
    }

    public static func filter(_ entries: [CatalogEntry], query: String, completeOnly: Bool = false) -> [CatalogEntry] {
        let pool = completeOnly ? entries.filter(\.isComplete) : entries
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return pool }
        return pool.filter { $0.displayName.lowercased().contains(needle) || $0.path.contains(needle) }
    }

    private static func collect(_ node: TrackerNode, path: String, base: String, qualifiers: [String],
                                into entries: inout [CatalogEntry]) {
        if node.spriteComplete > 0 {
            let name = qualifiers.isEmpty ? base : "\(base) (\(qualifiers.joined(separator: ", ")))"
            entries.append(CatalogEntry(path: path, displayName: name, isComplete: node.spriteComplete >= 2))
        }
        for (id, child) in node.subgroups {
            let label = cleanName(child.name)
            collect(child, path: "\(path)/\(id)", base: base,
                    qualifiers: label.isEmpty ? qualifiers : qualifiers + [label], into: &entries)
        }
    }

    private static func cleanName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    }
}

private struct TrackerNode: Decodable {
    let name: String
    let spriteComplete: Int
    let subgroups: [String: TrackerNode]

    enum CodingKeys: String, CodingKey {
        case name
        case spriteComplete = "sprite_complete"
        case subgroups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        spriteComplete = try container.decodeIfPresent(Int.self, forKey: .spriteComplete) ?? 0
        subgroups = try container.decodeIfPresent([String: TrackerNode].self, forKey: .subgroups) ?? [:]
    }
}
