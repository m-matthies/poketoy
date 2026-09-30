import Foundation
import Testing
@testable import PokeToyCore

@Suite struct FriendshipsTests {
    let a = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let b = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    let c = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

    @Test func keyIsOrderIndependent() {
        #expect(Friendships.key(a, b) == Friendships.key(b, a))
        #expect(Friendships.key(a, b) == "\(a.uuidString)+\(b.uuidString)")
    }

    @Test func levelsFollowPoints() {
        #expect(FriendshipLevel(points: 0) == .stranger)
        #expect(FriendshipLevel(points: 2) == .stranger)
        #expect(FriendshipLevel(points: 3) == .friend)
        #expect(FriendshipLevel(points: 9) == .friend)
        #expect(FriendshipLevel(points: 10) == .bestFriend)
        #expect(FriendshipLevel.stranger < .bestFriend)
    }

    @Test func addingRaisesScoreAndLevel() {
        var friendships = Friendships()
        friendships.add(a, b)
        friendships.add(b, a, 2)
        #expect(friendships.score(a, b) == 3)
        #expect(friendships.level(b, a) == .friend)
        friendships.add(a, a, 5)
        #expect(friendships.points.count == 1)
    }

    @Test func removingAPetDropsItsPairs() {
        var friendships = Friendships()
        friendships.add(a, b, 4)
        friendships.add(b, c, 4)
        friendships.remove(a)
        #expect(friendships.score(a, b) == 0)
        #expect(friendships.score(b, c) == 4)
    }

    @Test func malformedKeysAreDroppedAndReversedKeysNormalized() {
        let reversed = "\(b.uuidString)+\(a.uuidString)"
        let friendships = Friendships(points: ["garbage": 3, "A+B": 2, reversed: 4, Friendships.key(a, c): -1])
        #expect(friendships.points == [Friendships.key(a, b): 4])
    }

    @Test func bestFriendIsTheHighestBestFriendAmongCandidates() {
        var friendships = Friendships()
        friendships.add(a, b, 12)
        friendships.add(a, c, 15)
        #expect(friendships.bestFriend(of: a, among: [a, b, c]) == c)
        #expect(friendships.bestFriend(of: a, among: [b]) == b)
        friendships.remove(b)
        #expect(friendships.bestFriend(of: a, among: [b]) == nil)
        #expect(Friendships().bestFriend(of: a, among: [b, c]) == nil)
    }
}
