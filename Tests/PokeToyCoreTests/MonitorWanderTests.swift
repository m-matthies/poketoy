import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct MonitorWanderTests {
    let left = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                          visibleFrame: CGRect(x: 0, y: 50, width: 1000, height: 725))

    func world(rightFloor: CGFloat) -> World {
        let right = ScreenInfo(frame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
                               visibleFrame: CGRect(x: 1000, y: rightFloor, width: 1000, height: 775 - rightFloor))
        return World.build(screens: [left, right], windows: [], primaryScreenHeight: 800)
    }

    func run(_ brain: inout PetBrain, _ body: inout Body, world: World, seconds: Double,
             until: (Body) -> Bool) -> Bool {
        for _ in 0..<Int(seconds * 60) {
            brain.update(BrainContext(dt: 1.0 / 60, world: world, cursor: CGPoint(x: -5000, y: -5000), cursorMode: .off,
                                      halfWidth: 10, animationFinished: true), body: &body)
            Physics.step(&body, dt: 1.0 / 60, world: world)
            if until(body) { return true }
        }
        return false
    }

    @Test func petsWanderToTheNextScreen() {
        let world = world(rightFloor: 0)  // the neighbour's floor is lower: walk off the end
        var brain = PetBrain(seed: 1)
        var body = Body(position: CGPoint(x: 800, y: 50), surfaceID: -1)
        #expect(run(&brain, &body, world: world, seconds: 300) { $0.isGrounded && $0.position.x > 1000 })
    }

    @Test func petsJumpUpToAHigherNeighbourFloor() {
        let world = world(rightFloor: 150)
        var brain = PetBrain(seed: 2)
        var body = Body(position: CGPoint(x: 800, y: 50), surfaceID: -1)
        #expect(run(&brain, &body, world: world, seconds: 300) { $0.isGrounded && $0.position.x > 1000 })
    }

    @Test func wildPokemonStayOnTheirScreen() {
        let world = world(rightFloor: 0)
        var brain = PetBrain(seed: 3, personality: .wild)
        var body = Body(position: CGPoint(x: 800, y: 50), surfaceID: -1)
        #expect(!run(&brain, &body, world: world, seconds: 120) { $0.position.x > 1000 })
    }
}
