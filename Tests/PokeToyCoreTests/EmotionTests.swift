import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct EmotionTests {
    func emotions(_ events: [PlaygroundEvent], of id: UUID) -> [Emotion] {
        events.compactMap { event in
            if case .emotion(let pet, let emotion) = event, pet == id { return emotion }
            return nil
        }
    }

    func eaten(_ events: [PlaygroundEvent]) -> Bool {
        events.contains { if case .treatEaten = $0 { return true }; return false }
    }

    @Test func portraitFallbacksEndInNormal() {
        for emotion in Emotion.allCases {
            #expect(emotion.portraitNames.last == "Normal")
            #expect(emotion.portraitNames.count >= 2)
            #expect(!emotion.emoji.isEmpty)
        }
        #expect(Emotion.happy.portraitNames.first == "Happy")
        #expect(Emotion.joyous.portraitNames == ["Joyous", "Happy", "Normal"])
    }

    @Test func eatingIsJoyous() {
        var (playground, ids) = makePlayground([300])
        playground.dropTreat(.apple, at: CGPoint(x: 400, y: 60))
        let result = playUntil(&playground, seconds: 10) { _, events in eaten(events) }
        #expect(emotions(result.events, of: ids[0]).contains(.joyous))
    }

    @Test func latecomersAreSad() {
        var (playground, ids) = makePlayground([250, 700])
        playground.dropTreat(.apple, at: CGPoint(x: 400, y: 60))
        let result = playUntil(&playground, seconds: 10) { _, events in eaten(events) }
        #expect(emotions(result.events, of: ids[1]) == [.sad])
    }

    @Test func knockedOverHurts() {
        var (playground, ids) = makePlayground([500], scale: 2)
        let thrown = playground.addPet(metrics: .uniform(), at: CGPoint(x: 420, y: 120))
        playground.handle(.dragBegan, pet: thrown)
        playground.handle(.dragEnded(velocity: CGVector(dx: 600, dy: 0)), pet: thrown)
        let result = playUntil(&playground, seconds: 1) { p, events in emotions(events, of: ids[0]).contains(.pain) }
        #expect(result.met)
    }

    @Test func hardUserThrowLandsDizzy() {
        var (playground, ids) = makePlayground([500])
        playground.handle(.dragBegan, pet: ids[0])
        playground.movePet(ids[0], to: CGPoint(x: 500, y: 400))
        playground.handle(.dragEnded(velocity: CGVector(dx: 600, dy: 0)), pet: ids[0])
        let result = playUntil(&playground, seconds: 2) { _, events in emotions(events, of: ids[0]).contains(.dizzy) }
        #expect(result.met)

        var (gentle, others) = makePlayground([500])
        gentle.handle(.dragBegan, pet: others[0])
        gentle.movePet(others[0], to: CGPoint(x: 500, y: 400))
        gentle.handle(.dragEnded(velocity: .zero), pet: others[0])
        let events = play(&gentle, seconds: 2)
        #expect(!emotions(events, of: others[0]).contains(.dizzy))
    }

    @Test func bestFriendGreetingIsHappy() {
        var (playground, ids) = makePlayground([480, 520])
        playground.friendships.add(ids[0], ids[1], 10)
        playground.startMoment(0, 1, kind: .greet)
        #expect(emotions(playground.events, of: ids[0]) == [.happy])
        #expect(emotions(playground.events, of: ids[1]) == [.happy])

        var (strangers, others) = makePlayground([480, 520])
        strangers.startMoment(0, 1, kind: .greet)
        #expect(emotions(strangers.events, of: others[0]).isEmpty)
    }
}
