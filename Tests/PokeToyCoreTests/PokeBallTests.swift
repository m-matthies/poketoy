import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct PokeBallTests {
    @Test func petsRememberBeingInTheirBall() throws {
        let old = #"{"id": "00000000-0000-0000-0000-000000000025", "spritePath": "0025", "displayName": "Pikachu"}"#
        var record = try JSONDecoder().decode(PetRecord.self, from: Data(old.utf8))
        #expect(!record.inBall)
        record.inBall = true
        #expect(try JSONDecoder().decode(PetRecord.self, from: JSONEncoder().encode(record)).inBall)
    }

    @Test func aPetInItsBallKeepsItsFriends() {
        var (playground, ids) = makePlayground([300, 400])
        playground.friendships.add(ids[0], ids[1], 30)
        playground.seekAttention(ids[0])
        playground.stowPet(ids[0])
        #expect(playground.pet(ids[0]) == nil)
        #expect(playground.friendships.score(ids[0], ids[1]) == 30)
        #expect(!playground.isSeekingAttention || playground.attention[ids[0]] == nil)
        playground.removePet(ids[1])  // releasing still forgets friendships
        #expect(playground.friendships.score(ids[0], ids[1]) == 0)
    }
}
