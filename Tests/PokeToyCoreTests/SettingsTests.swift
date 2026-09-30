import Foundation
import Testing
@testable import PokeToyCore

@Suite struct SettingsTests {
    func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "PokeToyTests-\(UUID().uuidString)")!
    }

    @Test func defaultsToOnePikachu() {
        let settings = Settings.load(from: freshDefaults())
        #expect(settings == .default)
        #expect(settings.pets.map(\.spritePath) == ["0025"])
        #expect(settings.scale == 2)
        #expect(settings.cursorMode == .off)
        #expect(!settings.hidden)
    }

    @Test func roundTrips() {
        let defaults = freshDefaults()
        var settings = Settings.default
        settings.pets.append(PetRecord(spritePath: "0001", displayName: "Bulbasaur", position: CGPoint(x: 10, y: 20)))
        settings.hidden = true
        settings.cursorMode = .flee
        settings.scale = 3
        settings.save(to: defaults)
        #expect(Settings.load(from: defaults) == settings)
    }

    @Test func emptyPetListStaysEmpty() {
        let defaults = freshDefaults()
        var settings = Settings.default
        settings.pets = []
        settings.save(to: defaults)
        #expect(Settings.load(from: defaults).pets.isEmpty)
    }

    @Test func garbageFallsBackToDefault() {
        let defaults = freshDefaults()
        defaults.set(Data("nope".utf8), forKey: "settings")
        #expect(Settings.load(from: defaults) == .default)
    }

    @Test func toleratesMissingKeysUnknownModeAndBadScale() {
        let defaults = freshDefaults()
        defaults.set(Data(#"{"hidden": true, "cursorMode": "dance", "scale": 7}"#.utf8), forKey: "settings")
        let settings = Settings.load(from: defaults)
        #expect(settings.hidden)
        #expect(settings.cursorMode == .off)
        #expect(settings.scale == 3)
        #expect(settings.pets == Settings.default.pets)
    }

    @Test func roundTripsFriendshipsAndBestScore() {
        let defaults = freshDefaults()
        var settings = Settings.default
        settings.friendships = ["x+y": 4]
        settings.bestCatchScore = 725
        settings.save(to: defaults)
        #expect(Settings.load(from: defaults) == settings)
    }

    @Test func toleratesBadFriendshipsAndBestScore() {
        let defaults = freshDefaults()
        defaults.set(Data(#"{"friendships": "nope", "bestCatchScore": "high", "scale": 1}"#.utf8), forKey: "settings")
        let settings = Settings.load(from: defaults)
        #expect(settings.friendships.isEmpty)
        #expect(settings.bestCatchScore == 0)
        #expect(settings.scale == 1)
    }
}
