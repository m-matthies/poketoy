import Foundation

/// One species in an evolution chain and what it can evolve into.
public struct EvolutionNode: Equatable, Sendable {
    public let dex: Int
    public let name: String
    public let next: [EvolutionNode]
}

public enum Evolution {
    /// Treats a pet must eat (plus having a best friend) before it can evolve.
    public static let treatsNeeded = 15

    /// Parses a PokeAPI `evolution-chain` document.
    public static func parseChain(json: Data) throws -> EvolutionNode {
        try JSONDecoder().decode(ChainDocument.self, from: json).chain.node
    }

    /// The species `dex` can evolve into (empty for final forms or species not in the chain).
    public static func nextForms(in chain: EvolutionNode, after dex: Int) -> [Int] {
        if chain.dex == dex { return chain.next.map(\.dex) }
        for child in chain.next {
            let found = nextForms(in: child, after: dex)
            if !found.isEmpty || contains(child, dex) { return found }
        }
        return []
    }

    public static func isReady(treatsEaten: Int, hasBestFriend: Bool) -> Bool {
        treatsEaten >= treatsNeeded && hasBestFriend
    }

    /// The national dex number in a SpriteCollab path such as `0133/0000/0001`.
    public static func dexNumber(of path: String) -> Int? {
        path.split(separator: "/").first.flatMap { Int($0) }
    }

    /// The SpriteCollab path of a species' base form.
    public static func path(for dex: Int) -> String {
        String(format: "%04d", dex)
    }

    private static func contains(_ node: EvolutionNode, _ dex: Int) -> Bool {
        node.dex == dex || node.next.contains { contains($0, dex) }
    }

    /// The trailing number of a PokeAPI resource URL (`…/pokemon-species/133/` → 133).
    static func trailingNumber(_ url: String) -> Int? {
        url.split(separator: "/").last.flatMap { Int($0) }
    }

    private struct ChainDocument: Decodable {
        let chain: Link
    }

    private struct Link: Decodable {
        struct Species: Decodable {
            let name: String
            let url: String
        }

        let species: Species
        let evolvesTo: [Link]

        enum CodingKeys: String, CodingKey {
            case species
            case evolvesTo = "evolves_to"
        }

        var node: EvolutionNode {
            EvolutionNode(dex: Evolution.trailingNumber(species.url) ?? 0, name: species.name, next: evolvesTo.map(\.node))
        }
    }
}

/// What PokeAPI says about a species.
public struct SpeciesInfo: Equatable, Sendable {
    public let dex: Int
    public let isLegendary: Bool
    public let isMythical: Bool
    public let evolutionChainID: Int?
}

/// Fetches species and evolution-chain data from PokeAPI, caching every document on disk.
public actor EvolutionStore {
    public static let defaultRemoteBase = URL(string: "https://pokeapi.co/api/v2/")!

    private let cacheDirectory: URL
    private let remoteBase: URL
    private let session: URLSession

    public init(cacheDirectory: URL, remoteBase: URL = EvolutionStore.defaultRemoteBase, session: URLSession = .shared) {
        self.cacheDirectory = cacheDirectory
        self.remoteBase = remoteBase
        self.session = session
    }

    public func species(_ dex: Int) async throws -> SpeciesInfo {
        let data = try await document("pokemon-species/\(dex)")
        let raw = try JSONDecoder().decode(RawSpecies.self, from: data)
        return SpeciesInfo(dex: dex, isLegendary: raw.isLegendary, isMythical: raw.isMythical,
                           evolutionChainID: raw.evolutionChain.flatMap { Evolution.trailingNumber($0.url) })
    }

    /// The species `dex` can evolve into.
    public func nextForms(of dex: Int) async throws -> [Int] {
        guard let chainID = try await species(dex).evolutionChainID else { return [] }
        let chain = try Evolution.parseChain(json: try await document("evolution-chain/\(chainID)"))
        return Evolution.nextForms(in: chain, after: dex)
    }

    /// A PokeAPI document, from the cache when present.
    private func document(_ path: String) async throws -> Data {
        let cached = cacheDirectory.appendingPathComponent(path.replacingOccurrences(of: "/", with: "-") + ".json")
        if let data = try? Data(contentsOf: cached) { return data }
        let (data, response) = try await session.data(from: remoteBase.appendingPathComponent(path))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw SpriteStoreError.http(status: http.statusCode, path: path)
        }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: cached, options: .atomic)
        return data
    }

    private struct RawSpecies: Decodable {
        struct Link: Decodable { let url: String }
        let isLegendary: Bool
        let isMythical: Bool
        let evolutionChain: Link?

        enum CodingKeys: String, CodingKey {
            case isLegendary = "is_legendary"
            case isMythical = "is_mythical"
            case evolutionChain = "evolution_chain"
        }
    }
}
