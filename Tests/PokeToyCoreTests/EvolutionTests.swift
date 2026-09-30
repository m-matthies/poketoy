import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct EvolutionTests {
    func node(_ dex: Int, _ name: String, _ next: String = "") -> String {
        #"{"species": {"name": "\#(name)", "url": "https://pokeapi.co/api/v2/pokemon-species/\#(dex)/"}, "evolves_to": [\#(next)]}"#
    }

    var bulbasaurChain: String {
        #"{"id": 1, "chain": \#(node(1, "bulbasaur", node(2, "ivysaur", node(3, "venusaur"))))}"#
    }

    var eeveeChain: String {
        #"{"id": 67, "chain": \#(node(133, "eevee", [node(134, "vaporeon"), node(135, "jolteon"), node(196, "espeon")].joined(separator: ",")))}"#
    }

    func species(_ dex: Int, chain: Int, legendary: Bool = false) -> String {
        #"{"id": \#(dex), "is_legendary": \#(legendary), "is_mythical": false, "evolution_chain": {"url": "https://pokeapi.co/api/v2/evolution-chain/\#(chain)/"}}"#
    }

    @Test func parsesLinearChains() throws {
        let chain = try Evolution.parseChain(json: Data(bulbasaurChain.utf8))
        #expect(chain.dex == 1)
        #expect(Evolution.nextForms(in: chain, after: 1) == [2])
        #expect(Evolution.nextForms(in: chain, after: 2) == [3])
    }

    @Test func parsesBranchingChains() throws {
        let chain = try Evolution.parseChain(json: Data(eeveeChain.utf8))
        #expect(Evolution.nextForms(in: chain, after: 133) == [134, 135, 196])
    }

    @Test func finalFormsHaveNoNext() throws {
        let chain = try Evolution.parseChain(json: Data(bulbasaurChain.utf8))
        #expect(Evolution.nextForms(in: chain, after: 3).isEmpty)
        #expect(Evolution.nextForms(in: chain, after: 999).isEmpty)
    }

    @Test func readiness() {
        #expect(!Evolution.isReady(treatsEaten: 14, hasBestFriend: true))
        #expect(!Evolution.isReady(treatsEaten: 15, hasBestFriend: false))
        #expect(Evolution.isReady(treatsEaten: 15, hasBestFriend: true))
        #expect(Evolution.dexNumber(of: "0133/0000/0001") == 133)
        #expect(Evolution.dexNumber(of: "abc") == nil)
        #expect(Evolution.path(for: 25) == "0025")
    }

    func remote() throws -> URL {
        let base = makeTempDirectory()
        let species = base.appendingPathComponent("pokemon-species")
        let chains = base.appendingPathComponent("evolution-chain")
        try FileManager.default.createDirectory(at: species, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chains, withIntermediateDirectories: true)
        try Data(self.species(133, chain: 67).utf8).write(to: species.appendingPathComponent("133"))
        try Data(self.species(150, chain: 78, legendary: true).utf8).write(to: species.appendingPathComponent("150"))
        try Data(eeveeChain.utf8).write(to: chains.appendingPathComponent("67"))
        return base
    }

    @Test func storeFetchesAndCaches() async throws {
        let base = try remote()
        let store = EvolutionStore(cacheDirectory: makeTempDirectory(), remoteBase: base)
        #expect(try await store.nextForms(of: 133) == [134, 135, 196])
        try FileManager.default.removeItem(at: base)  // offline now
        #expect(try await store.nextForms(of: 133) == [134, 135, 196])
    }

    @Test func storeReportsLegendaries() async throws {
        let store = EvolutionStore(cacheDirectory: makeTempDirectory(), remoteBase: try remote())
        #expect(try await store.species(150).isLegendary)
        #expect(try await !store.species(133).isLegendary)
    }

    @Test func petRecordsDecodeWithoutTreatCount() throws {
        let json = #"{"id": "00000000-0000-0000-0000-000000000025", "spritePath": "0025", "displayName": "Pikachu"}"#
        let record = try JSONDecoder().decode(PetRecord.self, from: Data(json.utf8))
        #expect(record.treatsEaten == 0)
        var fed = record
        fed.treatsEaten = 7
        let again = try JSONDecoder().decode(PetRecord.self, from: JSONEncoder().encode(fed))
        #expect(again.treatsEaten == 7)
    }

    @Test func replacingMetricsKeepsThePet() {
        var (playground, ids) = makePlayground([300, 600])
        playground.friendships.add(ids[0], ids[1], 5)
        let position = playground.pet(ids[0])!.body.position
        playground.replaceMetrics(of: ids[0], with: .uniform(width: 48, height: 56))
        #expect(playground.pet(ids[0])?.metrics.frameSizes[.idle] == CGSize(width: 48, height: 56))
        #expect(playground.pet(ids[0])?.body.position == position)
        #expect(playground.friendships.score(ids[0], ids[1]) == 5)
    }
}
