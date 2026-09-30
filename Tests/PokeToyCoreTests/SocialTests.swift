import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct SocialTests {
    let cursorBetween = CGPoint(x: 500, y: 60)

    func startedMoment(_ events: [PlaygroundEvent]) -> Bool {
        events.contains { if case .momentStarted = $0 { return true }; return false }
    }

    @Test func petsThatMeetStartAMoment() {
        var (playground, _) = makePlayground([480, 520])
        // Follow mode with the cursor between them keeps both idle side by side.
        let result = playUntil(&playground, seconds: 10, cursor: cursorBetween, mode: .follow) { _, events in
            startedMoment(events)
        }
        #expect(result.met)
    }

    @Test func aCompletedMomentAddsFriendshipAndACooldown() {
        var (playground, ids) = makePlayground([480, 520])
        play(&playground, seconds: 15, cursor: cursorBetween, mode: .follow)
        #expect(playground.friendships.score(ids[0], ids[1]) >= 1)
        #expect((playground.pairCooldowns[Friendships.key(ids[0], ids[1])] ?? 0) > 0)
    }

    @Test func momentChoiceFollowsFriendship() {
        #expect(Playground.momentWeights(.stranger).map(\.weight) == [60, 15, 25])
        #expect(Playground.momentWeights(.friend).map(\.weight) == [40, 30, 30])
        #expect(Playground.momentWeights(.bestFriend).map(\.weight) == [30, 35, 35])
        var playground = Playground(seed: 9)
        var greets = 0
        for _ in 0..<3000 where playground.pickMoment(for: .stranger) == .greet { greets += 1 }
        #expect(Double(greets) / 3000 > 0.55 && Double(greets) / 3000 < 0.65)
    }

    @Test func greetingShowsHeartsByFriendship() {
        for (points, hearts) in [(0, 0), (3, 1), (10, 2)] {
            var (playground, ids) = makePlayground([480, 520])
            if points > 0 { playground.friendships.add(ids[0], ids[1], points) }
            playground.startMoment(0, 1, kind: .greet)
            #expect(playground.pet(ids[0])?.pose == Pose(anim: .greet, facing: .right, hearts: hearts,
                                                         token: playground.pet(ids[0])!.pose.token))
            #expect(playground.pet(ids[1])?.pose.facing == .left)
            #expect(playground.pet(ids[1])?.pose.hearts == hearts)
        }
    }

    @Test func tagChaserChasesThenBothStop() {
        var (playground, ids) = makePlayground([400, 600])
        playground.startMoment(0, 1, kind: .tag)
        let chaser = playground.moments[0].a
        let runner = playground.moments[0].b
        play(&playground, seconds: 0.5)
        let c = playground.pet(chaser)!, r = playground.pet(runner)!
        #expect(c.body.velocity.dx * (r.body.position.x - c.body.position.x) > 0)
        #expect(r.body.velocity.dx * (r.body.position.x - c.body.position.x) > 0)
        play(&playground, seconds: 4.8)
        #expect(playground.moments.isEmpty)
        #expect(playground.friendships.score(ids[0], ids[1]) == 1)
        #expect(playground.pet(ids[0])?.brain.script == nil)
        #expect(playground.pet(ids[1])?.brain.script == nil)
    }

    @Test func playFightAttackThenFlinch() {
        var (playground, ids) = makePlayground([480, 520])
        playground.startMoment(0, 1, kind: .playFight)
        let attacker = playground.moments[0].a
        let defender = playground.moments[0].b
        #expect(playground.pet(attacker)?.pose.anim == .attack)
        let flinch = playUntil(&playground, seconds: 2) { p, _ in p.pet(defender)?.pose.anim == .sad }
        #expect(flinch.met)
        play(&playground, seconds: 1.0 / 60)
        let a = playground.pet(attacker)!, d = playground.pet(defender)!
        #expect(d.body.velocity.dx * (d.body.position.x - a.body.position.x) > 0)
        play(&playground, seconds: 2)
        #expect(playground.moments.isEmpty)
        #expect(playground.friendships.score(ids[0], ids[1]) == 1)
    }

    @Test func interruptedGreetGivesNoFriendship() {
        var (playground, ids) = makePlayground([480, 520])
        playground.startMoment(0, 1, kind: .greet)
        playground.handle(.click, pet: ids[0])
        play(&playground, seconds: 0.1)
        #expect(playground.moments.isEmpty)
        #expect(playground.friendships.score(ids[0], ids[1]) == 0)
        #expect(playground.pet(ids[1])?.brain.script == nil)
    }

    @Test func removingAPartnerEndsTheMoment() {
        var (playground, ids) = makePlayground([400, 600])
        playground.startMoment(0, 1, kind: .tag)
        playground.removePet(ids[1])
        #expect(playground.moments.isEmpty)
        #expect(playground.pet(ids[0])?.brain.script == nil)
    }

    @Test func bestFriendsNapTogether() {
        var (playground, ids) = makePlayground([300, 600])
        playground.friendships.add(ids[0], ids[1], 10)
        let ok1 = playground.pets[0].fallAsleep()
        #expect(ok1)
        let result = playUntil(&playground, seconds: 8) { p, _ in p.pet(ids[1])?.brain.isSleeping == true }
        #expect(result.met)
        let gap = abs(playground.pet(ids[0])!.body.position.x - playground.pet(ids[1])!.body.position.x)
        #expect(gap < 40)
    }

    @Test func strangersDoNotNapTogether() {
        var (playground, ids) = makePlayground([300, 600])
        let ok2 = playground.pets[0].fallAsleep()
        #expect(ok2)
        play(&playground, seconds: 5)
        #expect(playground.pet(ids[1])?.brain.isSleeping == false)
    }

    @Test func bestFriendsSeekEachOtherOut() {
        var (playground, ids) = makePlayground([150, 850])
        playground.friendships.add(ids[0], ids[1], 10)
        let result = playUntil(&playground, seconds: 40) { p, _ in
            abs(p.pet(ids[0])!.body.position.x - p.pet(ids[1])!.body.position.x) < 100
        }
        #expect(result.met)
    }

    @Test func draggingTheAttackerDuringTheFlinchGivesNoFriendship() {
        var (playground, ids) = makePlayground([480, 520])
        playground.startMoment(0, 1, kind: .playFight)
        let attacker = playground.moments[0].a
        let defender = playground.moments[0].b
        let flinch = playUntil(&playground, seconds: 2) { p, _ in p.pet(defender)?.pose.anim == .sad }
        #expect(flinch.met)
        playground.handle(.dragBegan, pet: attacker)
        play(&playground, seconds: 2)
        #expect(playground.moments.isEmpty)
        #expect(playground.friendships.score(ids[0], ids[1]) == 0)
    }
}
