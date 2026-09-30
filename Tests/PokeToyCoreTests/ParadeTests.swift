import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct ParadeTests {
    /// Three pets on the floor who are all friends.
    func friends(_ xs: [CGFloat] = [300, 340, 380]) -> (Playground, [UUID]) {
        var (playground, ids) = makePlayground(xs)
        for a in ids.indices {
            for b in ids.indices where b > a { playground.friendships.add(ids[a], ids[b], 3) }
        }
        return (playground, ids)
    }

    @Test func friendsFollowTheLeader() {
        var (playground, ids) = friends()
        let started = playground.startParade(from: 0)
        #expect(started)
        let parade = playground.parades[0]
        #expect(parade.leader == ids[2])  // the rightmost, with more room to the right
        #expect(parade.followers == [ids[1], ids[0]])
        let before = ids.map { playground.pet($0)!.body.position.x }
        play(&playground, seconds: 2)
        let after = ids.map { playground.pet($0)!.body.position.x }
        for (b, a) in zip(before, after) { #expect(a > b + 40) }
    }

    @Test func followersKeepTheirSpacing() {
        var (playground, ids) = friends()
        playground.startParade(from: 0)
        play(&playground, seconds: 3)
        let xs = ids.map { playground.pet($0)!.body.position.x }
        let spacing = 2 * playground.pet(ids[0])!.halfWidth + 6
        #expect(abs((xs[2] - xs[1]) - spacing) < 10)
        #expect(abs((xs[1] - xs[0]) - spacing) < 10)
    }

    @Test func paradeEndsAndBuildsFriendship() {
        var (playground, ids) = friends()
        playground.startParade(from: 0)
        let events = play(&playground, seconds: 13)
        #expect(playground.parades.isEmpty)
        #expect(playground.friendships.score(ids[2], ids[1]) >= 4)  // +1 from the parade (a greeting may follow)
        #expect(playground.friendships.score(ids[2], ids[0]) >= 4)
        #expect(events.contains(.friendshipChanged))
        #expect(ids.allSatisfy { playground.pet($0)?.brain.script?.priority != 2 })
    }

    @Test func strangersDoNotParade() {
        var (playground, _) = makePlayground([300, 340, 380])
        let started = playground.startParade(from: 0)
        #expect(!started)
    }

    @Test func interruptingEndsTheParade() {
        var (playground, ids) = friends()
        playground.startParade(from: 0)
        play(&playground, seconds: 0.5)
        playground.handle(.click, pet: ids[1])
        play(&playground, seconds: 1.0 / 60)
        #expect(playground.parades.isEmpty)
        #expect(playground.pet(ids[2])?.brain.script == nil)
        #expect(playground.friendships.score(ids[2], ids[1]) == 3)
    }

    @Test func noParadesDuringAGame() {
        var (playground, _) = friends()
        playground.startGame(roster: [WildSpec(path: "0025", displayName: "Pikachu", metrics: .uniform())], seed: 1)
        let started = playground.startParade(from: 0)
        #expect(!started)
    }

    @Test func paradesStartByThemselves() {
        var (playground, _) = friends()
        let result = playUntil(&playground, seconds: 400) { p, _ in !p.parades.isEmpty }
        #expect(result.met)
    }
}
