import Foundation
import Testing
@testable import PokeToyCore

@Suite struct CatalogTests {
    let json = """
    {
      "0000": {"name": "Missingno_", "sprite_complete": 2, "canon": false, "subgroups": {}},
      "0025": {"name": "Pikachu", "sprite_complete": 2, "sprite_files": {"Walk": true}, "subgroups": {
        "0000": {"name": "", "sprite_complete": 0, "subgroups": {
          "0001": {"name": "Shiny", "sprite_complete": 2, "subgroups": {
            "0002": {"name": "Female", "sprite_complete": 2, "subgroups": {}}}},
          "0000": {"name": "", "sprite_complete": 0, "subgroups": {
            "0002": {"name": "Female", "sprite_complete": 2, "subgroups": {}}}}}},
        "0001": {"name": "Gigantamax", "sprite_complete": 0, "subgroups": {}},
        "0002": {"name": "Rock_Star", "sprite_complete": 1, "subgroups": {}}}},
      "0026": {"name": "Raichu", "sprite_complete": 0, "subgroups": {}}
    }
    """

    @Test func flattensFormsWithSprites() throws {
        let entries = try Catalog.parse(trackerJSON: Data(json.utf8))
        #expect(entries == [
            CatalogEntry(path: "0000", displayName: "Missingno"),
            CatalogEntry(path: "0025", displayName: "Pikachu"),
            CatalogEntry(path: "0025/0000/0000/0002", displayName: "Pikachu (Female)"),
            CatalogEntry(path: "0025/0000/0001", displayName: "Pikachu (Shiny)"),
            CatalogEntry(path: "0025/0000/0001/0002", displayName: "Pikachu (Shiny, Female)"),
            CatalogEntry(path: "0025/0002", displayName: "Pikachu (Rock Star)"),
        ])
    }

    @Test func toleratesMissingFields() throws {
        let entries = try Catalog.parse(trackerJSON: Data(#"{"0001": {"name": "Bulbasaur", "sprite_complete": 2}}"#.utf8))
        #expect(entries == [CatalogEntry(path: "0001", displayName: "Bulbasaur")])
    }

    @Test func rejectsInvalidJSON() {
        #expect(throws: (any Error).self) { try Catalog.parse(trackerJSON: Data("not json".utf8)) }
    }

    @Test func filtersByNameOrNumber() throws {
        let entries = try Catalog.parse(trackerJSON: Data(json.utf8))
        #expect(Catalog.filter(entries, query: "").count == 6)
        #expect(Catalog.filter(entries, query: "  SHINY ").map(\.path) == ["0025/0000/0001", "0025/0000/0001/0002"])
        #expect(Catalog.filter(entries, query: "25").count == 5)
        #expect(Catalog.filter(entries, query: "zzz").isEmpty)
    }
}
