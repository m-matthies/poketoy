import Testing
@testable import PokeToyCore

@Suite struct DirectionTests {
    @Test func rowOrderMatchesPMDSheets() {
        #expect(Direction.allCases == [.down, .downRight, .right, .upRight, .up, .upLeft, .left, .downLeft])
        #expect(Direction.down.rawValue == 0)
        #expect(Direction.downLeft.rawValue == 7)
    }

    @Test func picksDirectionFromVector() {
        #expect(Direction.from(dx: 1, dy: 0) == .right)
        #expect(Direction.from(dx: -1, dy: 0) == .left)
        #expect(Direction.from(dx: 0, dy: 1) == .up)
        #expect(Direction.from(dx: 0, dy: -1) == .down)
        #expect(Direction.from(dx: 1, dy: 1) == .upRight)
        #expect(Direction.from(dx: -1, dy: -1) == .downLeft)
        #expect(Direction.from(dx: 1, dy: -1) == .downRight)
        #expect(Direction.from(dx: 0, dy: 0) == .down)
    }
}
